import Foundation
import Combine

@MainActor
final class NotificationStore: ObservableObject {
    @Published private(set) var notifications: [AppNotification]

    private let storageKey = "notificationStore.notifications"
    private let processedEventsKey = "notificationStore.processedEventIDs"
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
        let userRole = userDefaults.string(forKey: "userRole") ?? "buyer"

        if userRole == "seller" {
            let sellerId = userDefaults.string(forKey: "sellerSellerId")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Self.sellerUserId(for: sellerId.isEmpty ? "SELL-01" : sellerId)
        }

        let buyerAccountCreated = userDefaults.bool(forKey: "buyerAccountCreated")
        let buyerEmail = userDefaults.string(forKey: "buyerEmail")?
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
        case .orderPlaced:
            handleNewOrder(event)
        case .orderStatusUpdated:
            handleBuyerOrderStatusUpdate(event)
        case .productFavorited:
            handleProductFavorited(event)
        default:
            break
        }
    }

    private func handlePriceDrop(_ event: CommerceEvent) {
        guard let productId = event.productId,
              let product = localProducts.product(withId: productId)
        else { return }

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
                    message: "\(product.name) just dropped to \(Money.format(cents: product.priceCents)). Grab it before it's gone.",
                    relatedProductId: product.id,
                    relatedSellerId: product.sellerId
                )
            )
        }
    }

    private func handleNewProduct(_ event: CommerceEvent) {
        guard let sellerId = event.sellerId,
              let productId = event.productId,
              let product = localProducts.product(withId: productId)
        else { return }

        let sellerName = resolvedSellerProfile(
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
                    message: "They just added \(product.name) under $10. Check it out.",
                    relatedProductId: product.id,
                    relatedSellerId: sellerId
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
                    relatedSellerId: shipment.sellerId
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
                item.productionPreviewURL != nil ||
                localProducts.product(withId: item.productId)?.productionPreviewURL != nil
            }

        let status = event.metadata["status"] ?? order.status.rawValue
        let content: (title: String, message: String)

        switch status {
        case OrderStatus.processing.rawValue:
            content = (
                "Your order is being made 👀",
                "Your \(firstItemName) is now in production." + (hasProductionPreview ? " Watch how it's made." : "")
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
                relatedSellerId: event.sellerId
            )
        )
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
                relatedSellerId: sellerId
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
                let alreadyCreated = notifications.contains {
                    $0.userId == sellerUserId &&
                    $0.relatedOrderId == order.id &&
                    $0.relatedSellerId == shipment.sellerId &&
                    $0.type == .system &&
                    $0.title == "Action Needed"
                }

                guard !alreadyCreated else { continue }

                appendNotification(
                    AppNotification(
                        userId: sellerUserId,
                        type: .system,
                        title: "Action Needed",
                        message: "Update your order status to keep buyers informed.",
                        relatedProductId: shipment.items.first?.productId,
                        relatedOrderId: order.id,
                        relatedSellerId: shipment.sellerId
                    )
                )
            }
        }
    }

    private func appendNotification(_ notification: AppNotification) {
        let alreadyExists = notifications.contains {
            $0.userId == notification.userId &&
            $0.type == notification.type &&
            $0.relatedOrderId == notification.relatedOrderId &&
            $0.relatedProductId == notification.relatedProductId &&
            $0.relatedSellerId == notification.relatedSellerId &&
            $0.title == notification.title &&
            $0.message == notification.message
        }

        guard !alreadyExists else { return }
        guard NotificationPreferences.isTypeEnabled(notification.type) else { return }

        notifications.insert(notification, at: 0)
        persistNotifications()
        deliveries.forEach { $0.deliver(notification) }
    }

    private func persistNotifications() {
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

    static let guestUserId = "guest"
}
