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
    private var processedEventIDs: Set<String>
    private var cancellables: Set<AnyCancellable> = []

    init(
        eventStore: CommerceEventStore,
        buyerEngagement: BuyerEngagementStore,
        localProducts: LocalProductStore,
        orderStore: OrderStore,
        deliveries: [NotificationDelivering]? = nil
    ) {
        self.eventStore = eventStore
        self.buyerEngagement = buyerEngagement
        self.localProducts = localProducts
        self.orderStore = orderStore
        self.deliveries = deliveries ?? [PushNotificationDeliveryBridge()]
        notifications = LocalCodableStore.load(key: storageKey, default: [])
        processedEventIDs = LocalCodableStore.load(key: processedEventsKey, default: Set<String>())
        migrateLegacyGuestNotificationsIfNeeded()

        processUnseenEvents(in: eventStore.recentEvents)
        evaluateActionNeededNotifications()

        eventStore.$recentEvents
            .sink { [weak self] events in
                self?.processUnseenEvents(in: events)
            }
            .store(in: &cancellables)
    }

    var currentUserId: String {
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
        case .productFavorited:
            handleProductFavorited(event)
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

        let recipients = buyerEngagement.snapshotsByIdentity.compactMap { userId, snapshot -> String? in
            if snapshot.favoriteProductIDs.contains(productId) {
                return userId
            }

            if snapshot.productInteractions[productId] != nil {
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
                    title: "Price Drop 🔥",
                    message: "\(productName) just dropped to \(Money.format(cents: currentPriceCents)). Grab it before it's gone.",
                    relatedProductId: productId,
                    relatedSellerId: sellerId,
                    dedupeKey: Self.inboxDedupeKey(eventId: event.id, semantic: "priceDrop.\(userId)")
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

        let recipients = buyerEngagement.snapshotsByIdentity.compactMap { userId, snapshot -> String? in
            if snapshot.followedSellerIDs.contains(sellerId) {
                return userId
            }

            let hasPurchasedFromSeller = snapshot.productInteractions.values.contains {
                $0.sellerId == sellerId && $0.interactionKinds.contains(.purchased)
            }
            return hasPurchasedFromSeller ? userId : nil
        }

        let uniqueRecipients = Array(Set(recipients))
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
                    dedupeKey: Self.inboxDedupeKey(eventId: event.id, semantic: "newProduct.\(userId)")
                )
            )
        }
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
                    title: "New Order 💰",
                    message: "You just received an order for \(firstItemName).",
                    relatedProductId: shipment.items.first?.productId,
                    relatedOrderId: order.id,
                    relatedSellerId: shipment.sellerId,
                    dedupeKey: Self.inboxDedupeKey(eventId: event.id, semantic: "orderPlaced.seller.\(shipment.id)")
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
                buyerMessage = "Order confirmed — production updates for \(firstName) will appear in Order details when they become available."
            } else {
                buyerMessage = "Order confirmed — we’ll keep you updated on \(firstName)."
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
                    dedupeKey: Self.inboxDedupeKey(eventId: event.id, semantic: "orderPlaced.buyer.\(order.id)")
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
                "Your order is being made 👀",
                hasProductionPreview
                    ? "Your \(firstItemName) is now in production. Check Order details for updates."
                    : "Your \(firstItemName) is now in production."
            )
        case OrderStatus.shipped.rawValue, OrderStatus.partiallyShipped.rawValue:
            content = (
                "Your order is on the way",
                "Your \(firstItemName) has shipped and is headed your way."
            )
        case OrderStatus.delivered.rawValue:
            content = (
                "Delivered",
                "Your \(firstItemName) has been delivered."
            )
        default:
            content = (
                "Order Update",
                "Your order status changed to \(status.capitalized)."
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
                dedupeKey: Self.inboxDedupeKey(eventId: event.id, semantic: "buyerOrderStatus.\(orderId).\(status)")
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

        switch shipmentStatus {
        case ShipmentStatus.shipped.rawValue:
            title = "Shipment update"
            message = "\(itemName) is on the way."
        case ShipmentStatus.delivered.rawValue:
            title = "Delivered"
            message = "\(itemName) was delivered."
        default:
            title = "Production update"
            message = "\(itemName) is now being prepared."
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
                    eventId: event.id,
                    semantic: "shipmentStatus.\(orderId).\(shipmentDisc).\(shipmentStatus)"
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
                    dedupeKey: Self.inboxDedupeKey(eventId: event.id, semantic: "makerVideoReady.\(order.id)")
                )
            )
        }
    }

    private func handleProductFavorited(_ event: CommerceEvent) {
        guard let sellerId = event.sellerId,
              let productId = event.productId,
              let product = localProducts.product(withId: productId)
        else { return }

        appendNotification(
            AppNotification(
                userId: Self.sellerUserId(for: sellerId),
                type: .itemFavorited,
                title: "Your product is getting attention 👀",
                message: "\(product.name) was just saved by a buyer.",
                relatedProductId: product.id,
                relatedSellerId: sellerId,
                dedupeKey: Self.inboxDedupeKey(eventId: event.id, semantic: "itemFavorited.\(productId)")
            )
        )
    }

    private func handleExchangeSubmitted(_ event: CommerceEvent) {
        guard let buyerIdentity = event.buyerIdentity,
              let exchangeRequestId = event.metadata["exchangeRequestId"] else { return }

        let status = event.metadata["status"] ?? ExchangeRequestStatus.submitted.rawValue
        let reason = event.metadata["reasonCode"] ?? ""
        let readableReason = ExchangeReasonCode.allCases.first(where: { $0.rawValue == reason })?.title ?? "issue"

        appendNotification(
            AppNotification(
                userId: buyerIdentity,
                type: .exchangeUpdate,
                title: "Exchange Submitted",
                message: "Your exchange request for \(readableReason.lowercased()) is now \(status.replacingOccurrences(of: "_", with: " ")).",
                relatedProductId: event.productId,
                relatedOrderId: event.orderId,
                relatedSellerId: event.sellerId,
                relatedExchangeRequestId: exchangeRequestId,
                dedupeKey: Self.inboxDedupeKey(eventId: event.id, semantic: "exchangeSubmitted.\(exchangeRequestId)")
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
            title = "More Info Needed"
            message = "Add more proof to keep your exchange request moving."
        case ExchangeRequestStatus.approved.rawValue:
            title = "Exchange Approved"
            message = "Your replacement request was approved."
        case ExchangeRequestStatus.denied.rawValue:
            title = "Exchange Update"
            message = "Your exchange request was denied."
        case ExchangeRequestStatus.replacementPreparing.rawValue:
            title = "Replacement Preparing"
            message = "Your replacement item is being prepared."
        case ExchangeRequestStatus.replacementShipped.rawValue:
            title = "Replacement Shipped"
            message = "Your replacement item is on the way."
        case ExchangeRequestStatus.replacementDelivered.rawValue:
            title = "Replacement Delivered"
            message = "Your replacement item was delivered."
        case ExchangeRequestStatus.cancelled.rawValue:
            title = "Exchange Cancelled"
            message = "Your exchange request was cancelled."
        default:
            title = "Exchange Update"
            message = "Your exchange request status changed."
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
                    eventId: event.id,
                    semantic: "exchangeStatus.\(exchangeRequestId).\(status)"
                )
            )
        )
    }

    private func evaluateActionNeededNotifications() {
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
                        title: "Action Needed",
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
        let deliveryChannelCount = deliveries.count
        inboxNotificationLogger.debug("appended \(notification.type.rawValue, privacy: .public) deliveries=\(deliveryChannelCount, privacy: .public)")
        deliveries.forEach { $0.deliver(notification) }
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

    private static func inboxDedupeKey(eventId: String, semantic: String) -> String {
        "\(eventId)|\(semantic)"
    }
}
