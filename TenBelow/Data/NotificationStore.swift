import Foundation
import Combine
import os

private let inboxNotificationLogger = Logger(subsystem: "com.innovativecodeworks.com.TenBelow", category: "InboxNotifications")

/// `UserDefaults` keys used only for resolving the **in-app notification inbox** identity (must stay aligned with `@AppStorage` elsewhere).
private enum InboxIdentityDefaults {
    static let userRole = "userRole"
    static let sellerSellerId = "sellerSellerId"
    static let buyerAccountCreated = "buyerAccountCreated"
    static let buyerEmail = "buyerEmail"
}

@MainActor
final class NotificationStore: ObservableObject {
    @Published private(set) var notifications: [AppNotification]

    private let storageKey = "notificationStore.notifications"
    private let processedEventsKey = "notificationStore.processedEventIDs"
    private let maxPersistedNotifications = 400
    private let deliveries: [NotificationDelivering]
    private let eventStore: CommerceEventStore
    private let buyerEngagement: BuyerEngagementStore
    private let localProducts: LocalProductStore
    private let orderStore: OrderStore
    private let bannerCenter: NotificationBannerCenter
    private var processedEventIDs: Set<String>
    private var cancellables: Set<AnyCancellable> = []
    /// Blocks delivery channels while rows are being *reconciled* rather than *delivered*:
    /// hydrating persisted state at launch, and the derived "action needed" sweep. Those rows
    /// still land in the inbox and the badge, they just never pop a banner.
    private var isDeliverySuppressed = true

    init(
        eventStore: CommerceEventStore,
        buyerEngagement: BuyerEngagementStore,
        localProducts: LocalProductStore,
        orderStore: OrderStore,
        deliveries: [NotificationDelivering]? = nil,
        bannerCenter: NotificationBannerCenter? = nil
    ) {
        self.eventStore = eventStore
        self.buyerEngagement = buyerEngagement
        self.localProducts = localProducts
        self.orderStore = orderStore
        self.bannerCenter = bannerCenter ?? .shared
        self.deliveries = deliveries ?? [PushNotificationDeliveryBridge()]
        notifications = LocalCodableStore.load(key: storageKey, default: [])
        processedEventIDs = LocalCodableStore.load(key: processedEventsKey, default: Set<String>())
        migrateLegacyGuestNotificationsIfNeeded()
        normalizeLegacyDedupeKeysIfNeeded()
        purgeNoisySellerFavoriteNotifications()

        processUnseenEvents(in: eventStore.recentEvents)
        evaluateActionNeededNotifications()
        isDeliverySuppressed = false

        eventStore.$recentEvents
            .sink { [weak self] events in
                self?.processUnseenEvents(in: events)
            }
            .store(in: &cancellables)
    }

    var currentUserId: String {
        Self.currentUserIdFromDefaults()
    }

    /// Identity resolution reads only `UserDefaults`, so callers outside the store (such as the
    /// APNs delegate) can resolve it without holding a store instance.
    static func currentUserIdFromDefaults() -> String {
        let userDefaults = UserDefaults.standard
        let userRole = userDefaults.string(forKey: InboxIdentityDefaults.userRole) ?? "buyer"

        if userRole == "seller" {
            let sellerId = userDefaults.string(forKey: InboxIdentityDefaults.sellerSellerId)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Self.sellerUserId(for: sellerId.isEmpty ? "SELL-01" : sellerId)
        }

        let buyerAccountCreated = userDefaults.bool(forKey: InboxIdentityDefaults.buyerAccountCreated)
        let buyerEmail = userDefaults.string(forKey: InboxIdentityDefaults.buyerEmail)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if buyerAccountCreated, !buyerEmail.isEmpty {
            return Self.buyerUserId(for: buyerEmail)
        }

        return Self.guestUserId
    }

    var currentNotifications: [AppNotification] {
        notifications(for: currentUserId)
    }

    func notifications(for userId: String) -> [AppNotification] {
        notifications
            .filter { $0.userId == userId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func unreadCount(for userId: String? = nil) -> Int {
        let resolvedUserId = userId ?? currentUserId
        return notifications.reduce(0) { partial, notification in
            partial + ((notification.userId == resolvedUserId && !notification.isRead) ? 1 : 0)
        }
    }

    func markAsRead(_ notificationId: String) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationId }) else { return }
        guard !notifications[index].isRead else { return }
        notifications[index].isRead = true
        persistNotifications()
    }

    func deleteNotification(_ notificationId: String) {
        let beforeCount = notifications.count
        notifications.removeAll { $0.id == notificationId }
        guard notifications.count != beforeCount else { return }
        persistNotifications()
    }

    /// Removes every inbox row for the signed-in buyer or seller identity.
    func clearCurrentUserNotifications() {
        let userId = currentUserId
        let beforeCount = notifications.count
        notifications.removeAll { $0.userId == userId }
        guard notifications.count != beforeCount else { return }
        persistNotifications()
    }

    func markAllCurrentUserNotificationsAsRead() {
        let userId = currentUserId
        var didChange = false
        for index in notifications.indices where notifications[index].userId == userId && !notifications[index].isRead {
            notifications[index].isRead = true
            didChange = true
        }
        guard didChange else { return }
        persistNotifications()
    }

    private func processUnseenEvents(in events: [CommerceEvent]) {
        for event in events.reversed() where !processedEventIDs.contains(event.id) {
            process(event)
            processedEventIDs.insert(event.id)
        }

        persistProcessedEventIDs()
        evaluateActionNeededNotifications()
    }

    private func process(_ event: CommerceEvent) {
        switch event.kind {
        case .productPriceChanged:
            handlePriceDrop(event)
        case .productCreated:
            handleNewProduct(event)
        case .productUpdated:
            handleProductUpdated(event)
        case .orderPlaced:
            handleNewOrder(event)
        case .orderStatusUpdated:
            handleBuyerOrderStatusUpdate(event)
        case .shipmentStatusUpdated:
            handleShipmentStatusUpdate(event)
        case .orderSupportRequestCreated:
            handleOrderSupportRequestCreated(event)
        case .orderSupportRequestUpdated:
            handleOrderSupportRequestUpdated(event)
        case .orderSupportMessageSent:
            handleOrderSupportMessageSent(event)
        case .productFavorited:
            break // Favorites are not seller-notified — too noisy for a marketplace inbox.
        case .exchangeSubmitted:
            handleExchangeSubmitted(event)
        case .exchangeStatusUpdated:
            handleExchangeStatusUpdated(event)
        default:
            break
        }
    }

    private func handlePriceDrop(_ event: CommerceEvent) {
        guard let productId = event.productId else { return }
        let product = localProducts.product(withId: productId)
        let productName = product?.name ?? event.metadata["name"] ?? "A product you viewed"
        let sellerId = event.sellerId ?? product?.sellerId
        let currentPriceCents = Int(event.metadata["newPriceCents"] ?? "") ?? product?.priceCents ?? 0

        let broadcastRecipients = Set(buyerUserIDsEligibleForSellerBroadcast(sellerId: sellerId))
        let recipients = buyerEngagement.snapshotsByIdentity.compactMap { userId, snapshot -> String? in
            // Favorited items always qualify; otherwise only followed / in-business sellers.
            if snapshot.favoriteProductIDs.contains(productId) {
                return userId
            }
            if broadcastRecipients.contains(userId) {
                return userId
            }
            return nil
        }

        let uniqueRecipients = Array(Set(recipients))
        guard !uniqueRecipients.isEmpty else { return }

        for userId in uniqueRecipients {
            appendNotification(
                AppNotification(
                    userId: userId,
                    type: .priceDrop,
                    title: "Price drop",
                    message: "\(productName) just dropped to \(Money.format(cents: currentPriceCents)). Grab it before it's gone.",
                    relatedProductId: productId,
                    relatedSellerId: sellerId,
                    dedupeKey: Self.inboxDedupeKey("priceDrop.\(userId)")
                )
            )
        }
    }

    private func handleNewProduct(_ event: CommerceEvent) {
        guard let sellerId = event.sellerId,
              let productId = event.productId
        else { return }

        let product = localProducts.product(withId: productId)
        let productName = product?.name ?? event.metadata["name"] ?? "a new upload"
        let sellerName = event.metadata["sellerName"] ??
            resolvedSellerProfile(
                sellerId: sellerId,
                storefrontProducts: localProducts.products
            )?.displayName ?? sellerId

        // Broadcast only to buyers who follow this seller or already have business with them.
        // Order messages / shipping alerts are separate and do not use this gate.
        let uniqueRecipients = buyerUserIDsEligibleForSellerBroadcast(sellerId: sellerId)
        guard !uniqueRecipients.isEmpty else { return }

        for userId in uniqueRecipients {
            appendNotification(
                AppNotification(
                    userId: userId,
                    type: .newProduct,
                    title: "New Drop from \(sellerName)",
                    message: "They just added \(productName). Check it out.",
                    relatedProductId: productId,
                    relatedSellerId: sellerId,
                    dedupeKey: Self.inboxDedupeKey("newProduct.\(userId)")
                )
            )
        }
    }

    /// Seller broadcast audience: followed sellers, or buyers with a prior purchase / order from that seller.
    private func buyerUserIDsEligibleForSellerBroadcast(sellerId: String?) -> [String] {
        let trimmedSellerId = sellerId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedSellerId.isEmpty else { return [] }

        var recipients = Set<String>()

        for (userId, snapshot) in buyerEngagement.snapshotsByIdentity {
            if snapshot.followedSellerIDs.contains(trimmedSellerId) {
                recipients.insert(userId)
                continue
            }

            let hasPurchasedFromSeller = snapshot.productInteractions.values.contains {
                $0.sellerId == trimmedSellerId && $0.interactionKinds.contains(.purchased)
            }
            if hasPurchasedFromSeller {
                recipients.insert(userId)
            }
        }

        for order in orderStore.orders {
            let hasBusinessWithSeller = order.shipments.contains {
                $0.sellerId.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedSellerId
            }
            guard hasBusinessWithSeller else { continue }
            guard let email = order.buyerEmail?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                !email.isEmpty
            else { continue }
            recipients.insert(Self.buyerUserId(for: email))
        }

        return Array(recipients)
    }

    private func handleNewOrder(_ event: CommerceEvent) {
        guard let orderId = event.orderId,
              let order = orderStore.order(withId: orderId)
        else { return }

        for shipment in order.shipments {
            let firstItemName = shipment.items.first?.productName ?? "a new item"

            appendNotification(
                AppNotification(
                    userId: Self.sellerUserId(for: shipment.sellerId),
                    type: .orderReceived,
                    title: "New order received",
                    message: "You received a new order for \(firstItemName). Open Orders to fulfill it.",
                    relatedProductId: shipment.items.first?.productId,
                    relatedOrderId: order.id,
                    relatedSellerId: shipment.sellerId,
                    dedupeKey: Self.inboxDedupeKey("orderPlaced.seller.\(order.id).\(shipment.sellerId)")
                )
            )
        }

        if let buyerKey = event.buyerIdentity, buyerKey != Self.guestUserId {
            let lineItems = order.shipments.flatMap(\.items)
            let metaName = event.metadata["firstProductName"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let firstName: String = {
                if let metaName, !metaName.isEmpty { return metaName }
                let fromOrder = lineItems.first?.productName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return fromOrder.isEmpty ? "your order" : fromOrder
            }()

            let hasMakerVideo: Bool = {
                if event.metadata["hasMakerVideo"] == "1" { return true }
                return lineItems.contains { line in
                    guard let s = line.productionPreviewURL?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
                    return !s.isEmpty
                }
            }()

            let buyerMessage: String
            if hasMakerVideo {
                buyerMessage = "Production updates for \(firstName) will appear in Order details when they become available."
            } else {
                buyerMessage = "We’ll keep you updated on \(firstName)."
            }

            appendNotification(
                AppNotification(
                    userId: buyerKey,
                    type: .orderStatusUpdate,
                    title: "Order confirmed",
                    message: buyerMessage,
                    relatedProductId: lineItems.first?.productId,
                    relatedOrderId: order.id,
                    relatedSellerId: order.shipments.first?.sellerId,
                    dedupeKey: Self.inboxDedupeKey("orderPlaced.buyer.\(order.id)")
                )
            )
        }
    }

    private func handleBuyerOrderStatusUpdate(_ event: CommerceEvent) {
        guard let orderId = event.orderId,
              let buyerIdentity = event.buyerIdentity,
              let order = orderStore.order(withId: orderId)
        else { return }

        let firstItemName = order.shipments.first?.items.first?.productName ?? "your order"
        let hasProductionPreview = order.shipments
            .flatMap(\.items)
            .contains { item in
                item.productionPreviewURL != nil
            }

        let status = event.metadata["status"] ?? order.status.rawValue
        let content: (title: String, message: String)

        switch status {
        case OrderStatus.processing.rawValue:
            content = (
                "Production started",
                hasProductionPreview
                    ? "Your \(firstItemName) is being made. Check Order details for updates."
                    : "Your \(firstItemName) is being made."
            )
        case OrderStatus.shipped.rawValue, OrderStatus.partiallyShipped.rawValue:
            content = (
                "Order shipped",
                "Your \(firstItemName) is on the way."
            )
        case OrderStatus.delivered.rawValue:
            content = (
                "Order delivered",
                "Your \(firstItemName) has been delivered."
            )
        case OrderStatus.cancelled.rawValue:
            content = (
                "Order cancelled",
                "Your \(firstItemName) was cancelled."
            )
        default:
            let readableStatus = status.replacingOccurrences(of: "_", with: " ")
            content = (
                readableStatus.capitalized,
                "Your order is now \(readableStatus)."
            )
        }

        appendNotification(
            AppNotification(
                userId: buyerIdentity,
                type: .orderStatusUpdate,
                title: content.title,
                message: content.message,
                relatedProductId: order.shipments.first?.items.first?.productId,
                relatedOrderId: order.id,
                relatedSellerId: event.sellerId,
                dedupeKey: Self.inboxDedupeKey("buyerOrderStatus.\(orderId).\(status)")
            )
        )
    }

    private func handleShipmentStatusUpdate(_ event: CommerceEvent) {
        guard let orderId = event.orderId else { return }
        let buyerIdentity =
            orderStore.order(withId: orderId).flatMap { order in
                order.buyerEmail
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .flatMap { $0.isEmpty ? nil : Self.buyerUserId(for: $0) }
            } ?? event.metadata["buyerUserId"].flatMap { $0.isEmpty ? nil : $0 }
        guard let buyerIdentity else { return }

        let shipmentStatus = event.metadata["shipmentStatus"] ?? "updated"
        let itemName = event.metadata["productName"] ?? "your item"
        let title: String
        let message: String

        let carrier = event.metadata["carrier"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tracking = event.metadata["trackingNumber"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trackingSuffix: String = {
            let parts = [carrier, tracking].filter { !$0.isEmpty }
            guard !parts.isEmpty else { return "" }
            return " Tracking: \(parts.joined(separator: " "))."
        }()

        switch shipmentStatus {
        case ShipmentStatus.shipped.rawValue:
            title = "Order shipped"
            message = "\(itemName) is on the way.\(trackingSuffix)"
        case ShipmentStatus.delivered.rawValue:
            title = "Order delivered"
            message = "\(itemName) has been delivered."
        case ShipmentStatus.cancelled.rawValue:
            title = "Shipment cancelled"
            message = "\(itemName) was cancelled for this order."
        case ShipmentStatus.preparing.rawValue:
            title = "Being prepared"
            message = "\(itemName) is now in production."
        default:
            if shipmentStatus.isEmpty || shipmentStatus == "updated" {
                title = "Being prepared"
                message = "\(itemName) is now in production."
            } else {
                let readableStatus = shipmentStatus.replacingOccurrences(of: "_", with: " ")
                title = readableStatus.capitalized
                message = "\(itemName) is now \(readableStatus)."
            }
        }

        let shipmentDisc = event.shipmentId ?? event.metadata["shipmentId"] ?? "na"
        appendNotification(
            AppNotification(
                userId: buyerIdentity,
                type: .orderStatusUpdate,
                title: title,
                message: message,
                relatedProductId: event.productId,
                relatedOrderId: orderId,
                relatedSellerId: event.sellerId,
                dedupeKey: Self.inboxDedupeKey(
                    "shipmentStatus.\(orderId).\(shipmentDisc).\(shipmentStatus)"
                )
            )
        )
    }

    private func handleProductUpdated(_ event: CommerceEvent) {
        guard event.metadata["update"] == "makerVideoReady",
              let productId = event.productId
        else { return }

        let matchingOrders = orderStore.orders.filter { order in
            order.shipments.contains { shipment in
                shipment.items.contains { $0.productId == productId }
            }
        }

        for order in matchingOrders {
            guard let buyerEmail = order.buyerEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !buyerEmail.isEmpty else { continue }

            let productName = event.metadata["name"] ??
                order.shipments
                    .flatMap(\.items)
                    .first(where: { $0.productId == productId })?
                    .productName ??
                "your item"

            appendNotification(
                AppNotification(
                    userId: Self.buyerUserId(for: buyerEmail),
                    type: .orderStatusUpdate,
                    title: "Production update is ready",
                    message: "A new production update for \(productName) is now available in your order details.",
                    relatedProductId: productId,
                    relatedOrderId: order.id,
                    relatedSellerId: event.sellerId,
                    dedupeKey: Self.inboxDedupeKey("makerVideoReady.\(order.id)")
                )
            )
        }
    }

    private func purgeNoisySellerFavoriteNotifications() {
        let beforeCount = notifications.count
        notifications.removeAll { $0.type == .itemFavorited }
        guard notifications.count != beforeCount else { return }
        persistNotifications()
    }

    private func handleOrderSupportRequestCreated(_ event: CommerceEvent) {
        guard let orderId = event.orderId,
              let sellerId = event.sellerId,
              let requestId = event.metadata["requestId"]
        else { return }

        let requestType = event.metadata["requestType"] ?? "cancel"
        let requestedBy = event.metadata["requestedBy"] ?? "buyer"
        let itemName = orderStore.order(withId: orderId)?
            .shipments
            .first(where: { $0.sellerId == sellerId })?
            .items
            .first?
            .productName ?? "an item"

        guard requestedBy == "buyer" else { return }

        let typeLabel = requestType == "refund" ? "Refund" : "Cancel"
        appendNotification(
            AppNotification(
                userId: Self.sellerUserId(for: sellerId),
                type: .orderSupportUpdate,
                title: "New buyer request",
                message: "A buyer submitted a \(typeLabel.lowercased()) request for \(itemName).",
                relatedOrderId: orderId,
                relatedSellerId: sellerId,
                dedupeKey: Self.inboxDedupeKey("supportCreated.seller.\(requestId)")
            )
        )
    }

    private func handleOrderSupportRequestUpdated(_ event: CommerceEvent) {
        guard let orderId = event.orderId,
              let sellerId = event.sellerId,
              let requestId = event.metadata["requestId"]
        else { return }

        let requestType = event.metadata["requestType"] ?? "cancel"
        let status = event.metadata["requestStatus"] ?? ""
        let requestedBy = event.metadata["requestedBy"] ?? "buyer"
        let itemName = orderStore.order(withId: orderId)?
            .shipments
            .first(where: { $0.sellerId == sellerId })?
            .items
            .first?
            .productName ?? "your item"

        let typeLabel = requestType == "refund" ? "Refund" : "Cancel"

        if ["approved", "denied"].contains(status), requestedBy == "buyer",
           let buyerIdentity = event.buyerIdentity {
            let title = status == "approved" ? "\(typeLabel) request approved" : "\(typeLabel) request denied"
            let message = status == "approved"
                ? "Your \(requestType) request for \(itemName) was approved."
                : "Your \(requestType) request for \(itemName) was denied."
            appendNotification(
                AppNotification(
                    userId: buyerIdentity,
                    type: .orderSupportUpdate,
                    title: title,
                    message: message,
                    relatedOrderId: orderId,
                    relatedSellerId: sellerId,
                    dedupeKey: Self.inboxDedupeKey("supportUpdated.buyer.\(requestId).\(status)")
                )
            )
        } else if status == "withdrawn" {
            appendNotification(
                AppNotification(
                    userId: Self.sellerUserId(for: sellerId),
                    type: .orderSupportUpdate,
                    title: "Request withdrawn",
                    message: "The buyer withdrew their \(requestType) request for order \(orderId).",
                    relatedOrderId: orderId,
                    relatedSellerId: sellerId,
                    dedupeKey: Self.inboxDedupeKey("supportWithdrawn.seller.\(requestId)")
                )
            )
        }
    }

    private func handleOrderSupportMessageSent(_ event: CommerceEvent) {
        guard let orderId = event.orderId,
              let sellerId = event.sellerId,
              let messageId = event.metadata["messageId"]
        else { return }

        let senderRole = event.metadata["senderRole"] ?? "buyer"
        let preview = event.metadata["text"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clipped = preview.count > 120 ? String(preview.prefix(117)) + "…" : preview
        let body = clipped.isEmpty ? "Open the order thread to read the message." : clipped

        if senderRole == "buyer" {
            appendNotification(
                AppNotification(
                    userId: Self.sellerUserId(for: sellerId),
                    type: .orderSupportUpdate,
                    title: "Buyer message",
                    message: body,
                    relatedOrderId: orderId,
                    relatedSellerId: sellerId,
                    dedupeKey: Self.inboxDedupeKey("supportMessage.seller.\(messageId)")
                )
            )
        } else if let buyerIdentity = event.buyerIdentity {
            appendNotification(
                AppNotification(
                    userId: buyerIdentity,
                    type: .orderSupportUpdate,
                    title: "Seller message",
                    message: body,
                    relatedOrderId: orderId,
                    relatedSellerId: sellerId,
                    dedupeKey: Self.inboxDedupeKey("supportMessage.buyer.\(messageId)")
                )
            )
        }
    }

    private func handleExchangeSubmitted(_ event: CommerceEvent) {
        guard let buyerIdentity = event.buyerIdentity,
              let exchangeRequestId = event.metadata["exchangeRequestId"] else { return }

        let reason = event.metadata["reasonCode"] ?? ""
        let readableReason = ExchangeReasonCode.allCases.first(where: { $0.rawValue == reason })?.title ?? "issue"

        appendNotification(
            AppNotification(
                userId: buyerIdentity,
                type: .exchangeUpdate,
                title: "Exchange submitted",
                message: "Your request for \(readableReason.lowercased()) was submitted.",
                relatedProductId: event.productId,
                relatedOrderId: event.orderId,
                relatedSellerId: event.sellerId,
                relatedExchangeRequestId: exchangeRequestId,
                dedupeKey: Self.inboxDedupeKey("exchangeSubmitted.\(exchangeRequestId)")
            )
        )
    }

    private func handleExchangeStatusUpdated(_ event: CommerceEvent) {
        guard let buyerIdentity = event.buyerIdentity,
              let exchangeRequestId = event.metadata["exchangeRequestId"] else { return }

        let status = event.metadata["status"] ?? ""
        let title: String
        let message: String

        switch status {
        case ExchangeRequestStatus.awaitingBuyerProof.rawValue:
            title = "More info needed"
            message = "Add more proof to keep your exchange request moving."
        case ExchangeRequestStatus.approved.rawValue:
            title = "Exchange approved"
            message = "Your replacement request was approved."
        case ExchangeRequestStatus.denied.rawValue:
            title = "Exchange declined"
            message = "Your exchange request wasn't approved."
        case ExchangeRequestStatus.replacementPreparing.rawValue:
            title = "Replacement preparing"
            message = "Your replacement is being prepared."
        case ExchangeRequestStatus.replacementShipped.rawValue:
            title = "Replacement shipped"
            message = "Your replacement is on the way."
        case ExchangeRequestStatus.replacementDelivered.rawValue:
            title = "Replacement delivered"
            message = "Your replacement was delivered."
        case ExchangeRequestStatus.cancelled.rawValue:
            title = "Exchange cancelled"
            message = "Your exchange request was cancelled."
        default:
            let readableStatus = status.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if readableStatus.isEmpty {
                title = "Exchange update"
                message = "Your exchange request status changed."
            } else {
                title = readableStatus.capitalized
                message = "Your exchange request is now \(readableStatus)."
            }
        }

        appendNotification(
            AppNotification(
                userId: buyerIdentity,
                type: .exchangeUpdate,
                title: title,
                message: message,
                relatedProductId: event.productId,
                relatedOrderId: event.orderId,
                relatedSellerId: event.sellerId,
                relatedExchangeRequestId: exchangeRequestId,
                dedupeKey: Self.inboxDedupeKey(
                    "exchangeStatus.\(exchangeRequestId).\(status)"
                )
            )
        )
    }

    /// Derived from order age rather than from a discrete event, so it is reconciled into the
    /// inbox without a banner. Otherwise the first orders refresh after launch would pop a
    /// banner for a nudge the seller may have already seen days ago.
    private func evaluateActionNeededNotifications() {
        let wasSuppressed = isDeliverySuppressed
        isDeliverySuppressed = true
        defer { isDeliverySuppressed = wasSuppressed }

        let threshold: TimeInterval = 60 * 60 * 24
        let now = Date.now

        for order in orderStore.orders {
            for shipment in order.shipments where shipment.status == .preparing {
                let orderAge = now.timeIntervalSince(order.createdAt)
                guard orderAge >= threshold else { continue }

                let sellerUserId = Self.sellerUserId(for: shipment.sellerId)

                appendNotification(
                    AppNotification(
                        userId: sellerUserId,
                        type: .system,
                        title: "Action needed",
                        message: "Update your order status to keep buyers informed.",
                        relatedProductId: shipment.items.first?.productId,
                        relatedOrderId: order.id,
                        relatedSellerId: shipment.sellerId,
                        dedupeKey: "actionNeeded.stalePreparing.\(order.id).\(shipment.id)"
                    )
                )
            }
        }
    }

    private func appendNotification(_ notification: AppNotification) {
        let alreadyExists: Bool
        if let dedupeKey = notification.dedupeKey {
            alreadyExists = notifications.contains { $0.dedupeKey == dedupeKey }
        } else {
            alreadyExists = notifications.contains {
                $0.userId == notification.userId &&
                $0.type == notification.type &&
                $0.relatedOrderId == notification.relatedOrderId &&
                $0.relatedProductId == notification.relatedProductId &&
                $0.relatedSellerId == notification.relatedSellerId &&
                $0.title == notification.title &&
                $0.message == notification.message
            }
        }

        guard !alreadyExists else {
            inboxNotificationLogger.debug("skip duplicate inbox row (dedupeKey=\(notification.dedupeKey ?? "nil", privacy: .public))")
            return
        }
        guard NotificationPreferences.isTypeEnabled(notification.type) else {
            inboxNotificationLogger.debug("skip type disabled in prefs (\(notification.type.rawValue, privacy: .public))")
            return
        }

        notifications.insert(notification, at: 0)
        persistNotifications()

        // Reaching here means the row did not exist, so this is the first time TenBelow has
        // seen the event. Reconciliation passes replay known state and are not deliveries.
        guard !isDeliverySuppressed else { return }

        let deliveryChannelCount = deliveries.count
        inboxNotificationLogger.debug("appended \(notification.type.rawValue, privacy: .public) deliveries=\(deliveryChannelCount, privacy: .public)")
        deliveries.forEach { $0.deliver(notification) }

        guard notification.userId == currentUserId else { return }
        bannerCenter.deliver(
            notification,
            presentationKey: Self.bannerPresentationKey(for: notification),
            source: .localEvent
        )
    }

    /// Banner delivery identity. Prefers the stable domain dedupe key; the row id is only a
    /// last resort for legacy rows that predate dedupe keys.
    private static func bannerPresentationKey(for notification: AppNotification) -> String {
        if let dedupeKey = notification.dedupeKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !dedupeKey.isEmpty {
            return "inbox:\(dedupeKey)"
        }
        return "row:\(notification.id)"
    }

    private func persistNotifications() {
        if notifications.count > maxPersistedNotifications {
            notifications = Array(notifications.prefix(maxPersistedNotifications))
        }
        LocalCodableStore.save(notifications, key: storageKey)
    }

    private func migrateLegacyGuestNotificationsIfNeeded() {
        let newKey = GuestInstallIdentity.userKey
        guard notifications.contains(where: { $0.userId == "guest" }) else { return }
        notifications = notifications.map { note in
            guard note.userId == "guest" else { return note }
            return AppNotification(
                id: note.id,
                userId: newKey,
                type: note.type,
                title: note.title,
                message: note.message,
                relatedProductId: note.relatedProductId,
                relatedOrderId: note.relatedOrderId,
                relatedSellerId: note.relatedSellerId,
                relatedExchangeRequestId: note.relatedExchangeRequestId,
                dedupeKey: note.dedupeKey,
                isRead: note.isRead,
                createdAt: note.createdAt
            )
        }
        LocalCodableStore.save(notifications, key: storageKey)
    }

    /// Rewrites `"<eventUUID>|<semantic>"` dedupe keys written by earlier builds down to the
    /// stable `"<semantic>"` form, then collapses the duplicate rows those unstable keys let
    /// through. Read state is preserved: if any copy was read, the survivor stays read.
    private func normalizeLegacyDedupeKeysIfNeeded() {
        guard notifications.contains(where: { ($0.dedupeKey ?? "").contains("|") }) else { return }

        let normalized = notifications.map { note -> AppNotification in
            guard let dedupeKey = note.dedupeKey,
                  let separatorIndex = dedupeKey.firstIndex(of: "|")
            else { return note }

            let semantic = String(dedupeKey[dedupeKey.index(after: separatorIndex)...])
            guard !semantic.isEmpty else { return note }

            return AppNotification(
                id: note.id,
                userId: note.userId,
                type: note.type,
                title: note.title,
                message: note.message,
                relatedProductId: note.relatedProductId,
                relatedOrderId: note.relatedOrderId,
                relatedSellerId: note.relatedSellerId,
                relatedExchangeRequestId: note.relatedExchangeRequestId,
                dedupeKey: semantic,
                isRead: note.isRead,
                createdAt: note.createdAt
            )
        }

        var survivorIndexByKey: [String: Int] = [:]
        var collapsed: [AppNotification] = []
        for note in normalized.sorted(by: { $0.createdAt > $1.createdAt }) {
            guard let dedupeKey = note.dedupeKey else {
                collapsed.append(note)
                continue
            }
            if let existingIndex = survivorIndexByKey[dedupeKey] {
                if note.isRead {
                    collapsed[existingIndex].isRead = true
                }
                continue
            }
            survivorIndexByKey[dedupeKey] = collapsed.count
            collapsed.append(note)
        }

        let removedCount = notifications.count - collapsed.count
        notifications = collapsed
        persistNotifications()
        inboxNotificationLogger.debug("normalized legacy dedupe keys, collapsed \(removedCount, privacy: .public) rows")
    }

    private func persistProcessedEventIDs() {
        LocalCodableStore.save(processedEventIDs, key: processedEventsKey)
    }

    static func sellerUserId(for sellerId: String) -> String {
        "seller:\(sellerId)"
    }

    static func buyerUserId(for buyerEmail: String) -> String {
        "buyer:\(buyerEmail)"
    }

    static var guestUserId: String { GuestInstallIdentity.userKey }

    /// Identity for an inbox row **and** for banner delivery.
    ///
    /// This must stay derived purely from the domain (order / shipment / message /
    /// request / exchange ids plus status) and must never include `CommerceEvent.id`,
    /// which is a fresh UUID each time an event is recorded. Mixing the event UUID in
    /// made every re-emitted event look brand new, which duplicated inbox rows and
    /// replayed banners.
    private static func inboxDedupeKey(_ semantic: String) -> String {
        semantic
    }
}
