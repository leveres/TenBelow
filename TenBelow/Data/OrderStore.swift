import Foundation
import Combine

enum SellerShipmentAction: String {
    case startProcessing
    case markShipped
    case markDelivered
    case updateTracking

    var buttonTitle: String {
        switch self {
        case .startProcessing:
            return "Start Production"
        case .markShipped:
            return "Mark Shipped"
        case .markDelivered:
            return "Mark Delivered"
        case .updateTracking:
            return "Update Tracking"
        }
    }
}

@MainActor
final class OrderStore: ObservableObject {
    @Published private(set) var orders: [Order]
    @Published private(set) var isRefreshing = false
    @Published var refreshError: String?
    @Published var shipmentActionError: String?
    @Published var productionPreviewActionError: String?
    @Published var orderSupportError: String?

    private let storageKey = "orderStore.orders"
    private let eventStore: CommerceEventStore

    init(eventStore: CommerceEventStore) {
        self.eventStore = eventStore
        let storedOrders: [Order] = LocalCodableStore.load(
            key: storageKey,
            default: [Order]()
        )
        #if DEBUG
        orders = storedOrders.isEmpty ? SampleOrders.data : storedOrders
        if storedOrders.isEmpty {
            persist()
        }
        #else
        orders = storedOrders
        #endif
    }

    func order(withId orderId: String) -> Order? {
        orders.first(where: { $0.id == orderId })
    }

    func refreshBuyerOrders(email: String?) async {
        let normalizedEmail = email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !normalizedEmail.isEmpty else { return }

        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }

        do {
            let serverOrders = try await OrdersAPI.fetchBuyerOrders(email: normalizedEmail)
            mergeServerOrders(serverOrders)
            refreshError = nil
        } catch is CancellationError {
            // Task was cancelled; don't treat as an error.
        } catch {
            refreshError = orders.isEmpty
                ? "Couldn't load orders. Pull to refresh or try again later."
                : "Showing saved orders until the latest updates come in."
        }
    }

    func refreshSellerOrders(sellerId: String) async {
        let normalizedSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSellerId.isEmpty else { return }

        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }

        do {
            let serverOrders = try await OrdersAPI.fetchSellerOrders(sellerId: normalizedSellerId)
            mergeServerOrders(serverOrders)
            refreshError = nil
        } catch is CancellationError {
            // Task was cancelled; don't treat as an error.
        } catch {
            refreshError = orders.isEmpty
                ? "Couldn't load orders. Pull to refresh or try again later."
                : "Showing saved orders until the latest updates come in."
        }
    }

    @discardableResult
    func placeOrder(
        orderId: String,
        items: [CartItem],
        buyerEmail: String?,
        shipToCity: String?,
        shipToState: String?
    ) -> Order {
        let groupedItems = Dictionary(grouping: items, by: { $0.product.sellerId })
        let shipments = groupedItems
            .sorted { $0.key < $1.key }
            .map { sellerId, cartItems in
                makeShipment(sellerId: sellerId, items: cartItems)
            }

        let order = Order(
            id: orderId,
            createdAt: .now,
            status: .placed,
            buyerEmail: buyerEmail,
            shipToCity: shipToCity,
            shipToState: shipToState,
            currency: "USD",
            totalCents: items.reduce(0) { $0 + ($1.product.priceCents * $1.quantity) },
            shipments: shipments
        )

        orders.insert(order, at: 0)
        persist()

        let firstProduct = items.first?.product
        let trimmedName = firstProduct?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let firstProductName = trimmedName.isEmpty ? "your order" : trimmedName
        let hasMakerVideo = shipments
            .flatMap(\.items)
            .contains { ($0.productionPreviewURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) }

        eventStore.record(
            CommerceEvent(
                kind: .orderPlaced,
                buyerIdentity: buyerIdentityKey,
                orderId: order.id,
                metadata: [
                    "sellerCount": "\(shipments.count)",
                    "itemCount": "\(order.totalItemsCount)",
                    "firstProductName": firstProductName,
                    "hasMakerVideo": hasMakerVideo ? "1" : "0"
                ]
            )
        )

        return order
    }

    func nextAction(for shipment: Shipment, order: Order) -> SellerShipmentAction? {
        switch shipment.status {
        case .delivered, .cancelled:
            return nil
        case .shipped:
            return .markDelivered
        case .preparing:
            return order.status == .placed ? .startProcessing : .markShipped
        }
    }

    func canUpdateTracking(for shipment: Shipment) -> Bool {
        shipment.status == .shipped || shipment.status == .delivered
    }

    func perform(
        _ action: SellerShipmentAction,
        orderId: String,
        shipmentId: String,
        sellerId: String,
        carrier: String? = nil,
        trackingNumber: String? = nil
    ) {
        guard let orderIndex = orders.firstIndex(where: { $0.id == orderId }) else { return }
        guard let shipmentIndex = orders[orderIndex].shipments.firstIndex(where: { $0.id == shipmentId && $0.sellerId == sellerId }) else { return }

        let timestamp = Date.now
        let previousStatus = orders[orderIndex].status

        switch action {
        case .startProcessing:
            orders[orderIndex].status = .processing
        case .markShipped:
            orders[orderIndex].shipments[shipmentIndex].status = .shipped
            orders[orderIndex].shipments[shipmentIndex].shippedAt = timestamp
            orders[orderIndex].shipments[shipmentIndex].carrier = carrier
            orders[orderIndex].shipments[shipmentIndex].trackingNumber = trackingNumber
        case .markDelivered:
            orders[orderIndex].shipments[shipmentIndex].status = .delivered
            orders[orderIndex].shipments[shipmentIndex].deliveredAt = timestamp
        case .updateTracking:
            orders[orderIndex].shipments[shipmentIndex].carrier = carrier
            orders[orderIndex].shipments[shipmentIndex].trackingNumber = trackingNumber
        }

        orders[orderIndex].status = derivedOrderStatus(from: orders[orderIndex].shipments, current: orders[orderIndex].status)
        persist()

        let shipment = orders[orderIndex].shipments[shipmentIndex]
        eventStore.record(
            CommerceEvent(
                kind: .shipmentStatusUpdated,
                buyerIdentity: buyerIdentityKey,
                productId: shipment.items.first?.productId,
                orderId: orderId,
                shipmentId: shipmentId,
                sellerId: sellerId,
                metadata: [
                    "action": action.rawValue,
                    "shipmentStatus": shipment.status.rawValue,
                    "productName": shipment.items.first?.productName ?? "your item",
                    "carrier": shipment.carrier ?? "",
                    "trackingNumber": shipment.trackingNumber ?? "",
                    "buyerUserId": buyerIdentityKey
                ]
            )
        )

        if previousStatus != orders[orderIndex].status {
            eventStore.record(
                CommerceEvent(
                    kind: .orderStatusUpdated,
                    buyerIdentity: buyerIdentityKey,
                    orderId: orderId,
                    sellerId: sellerId,
                    metadata: [
                        "status": orders[orderIndex].status.rawValue
                    ]
                )
            )
        }
    }

    func performShipmentAction(
        _ action: SellerShipmentAction,
        orderId: String,
        shipmentId: String,
        sellerId: String,
        carrier: String? = nil,
        trackingNumber: String? = nil
    ) async {
        shipmentActionError = nil
        do {
            let updatedOrder = try await OrdersAPI.performShipmentAction(
                action,
                orderId: orderId,
                shipmentId: shipmentId,
                sellerId: sellerId,
                carrier: carrier,
                trackingNumber: trackingNumber
            )
            upsertOrder(updatedOrder)
        } catch {
            let nsError = error as NSError
            let isConnectivityIssue = nsError.domain == NSURLErrorDomain

            if isConnectivityIssue {
                perform(
                    action,
                    orderId: orderId,
                    shipmentId: shipmentId,
                    sellerId: sellerId,
                    carrier: carrier,
                    trackingNumber: trackingNumber
                )
                shipmentActionError = "Saved locally — will sync when connected."
            } else {
                shipmentActionError = error.localizedDescription
            }
        }
    }

    func updateOrderProductionPreview(
        orderId: String,
        shipmentId: String,
        sellerId: String,
        orderItemId: String,
        productionPreviewURL: String?,
        removeProductionPreview: Bool = false
    ) async {
        productionPreviewActionError = nil
        do {
            let updatedOrder = try await OrdersAPI.updateOrderProductionPreview(
                orderId: orderId,
                shipmentId: shipmentId,
                sellerId: sellerId,
                orderItemId: orderItemId,
                productionPreviewURL: productionPreviewURL,
                removeProductionPreview: removeProductionPreview
            )
            upsertOrder(updatedOrder)
        } catch {
            productionPreviewActionError = error.localizedDescription
        }
    }

    func applyExchangeRequests(_ exchangeRequests: [ExchangeRequest], to orderId: String) {
        guard let orderIndex = orders.firstIndex(where: { $0.id == orderId }) else { return }

        var order = orders[orderIndex]
        let requestsByItemID = Dictionary(grouping: exchangeRequests, by: \.orderItemId)
        let latestOrderRequest = exchangeRequests.max { lhs, rhs in
            lhs.updatedAt < rhs.updatedAt
        }

        for shipmentIndex in order.shipments.indices {
            let shipment = order.shipments[shipmentIndex]
            for itemIndex in shipment.items.indices {
                let item = shipment.items[itemIndex]
                let itemRequests = requestsByItemID[item.id] ?? []
                let latestItemRequest = itemRequests.max { lhs, rhs in
                    lhs.updatedAt < rhs.updatedAt
                }
                let completedCount = itemRequests.reduce(0) { partial, request in
                    partial + (request.status.countsTowardExchangeLimit ? 1 : 0)
                }
                let hasActiveRequest = itemRequests.contains { $0.status.isActive }

                order.shipments[shipmentIndex].items[itemIndex].hasExchangeRequest = hasActiveRequest || completedCount > 0
                order.shipments[shipmentIndex].items[itemIndex].exchangeRequestId = latestItemRequest?.id
                order.shipments[shipmentIndex].items[itemIndex].exchangeCount = completedCount
                order.shipments[shipmentIndex].items[itemIndex].deliveredAt = item.deliveredAt ?? shipment.deliveredAt
                order.shipments[shipmentIndex].items[itemIndex].fulfillmentStatus = item.fulfillmentStatus ?? shipment.status
                order.shipments[shipmentIndex].items[itemIndex].orderStatus = item.orderStatus ?? order.status
            }
        }

        let completedOrderCount = exchangeRequests.reduce(0) { partial, request in
            partial + (request.status.countsTowardExchangeLimit ? 1 : 0)
        }

        order.hasExchangeRequest = exchangeRequests.contains(where: { $0.status.isActive }) || completedOrderCount > 0
        order.exchangeRequestId = latestOrderRequest?.id
        order.exchangeCount = completedOrderCount
        order.deliveredAt = order.deliveredAt ?? order.shipments.compactMap(\.deliveredAt).max()

        orders[orderIndex] = order
        persist()
    }

    private var buyerIdentityKey: String {
        let userDefaults = UserDefaults.standard
        let email = userDefaults.string(forKey: "buyerEmail")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let email, !email.isEmpty {
            return "buyer:\(email)"
        }

        return GuestInstallIdentity.userKey
    }

    private func makeShipment(sellerId: String, items: [CartItem]) -> Shipment {
        let seller = resolvedSellerProfile(
            sellerId: sellerId,
            storefrontProducts: items.map(\.product)
        )
        let maxShipDays = items.map { $0.product.shipsInDays.upperBound }.max() ?? 4

        return Shipment(
            id: "SHP-\(UUID().uuidString.prefix(8).uppercased())",
            sellerId: sellerId,
            sellerName: seller?.displayName ?? sellerId,
            sellerHandle: seller?.handle,
            status: .preparing,
            shipByDate: Calendar.current.date(byAdding: .day, value: maxShipDays, to: .now),
            carrier: nil,
            trackingNumber: nil,
            shippedAt: nil,
            deliveredAt: nil,
            items: items.map { item in
                OrderLineItem(
                    id: "LI-\(UUID().uuidString.prefix(8).uppercased())",
                    productId: item.product.id,
                    productName: item.product.name,
                    unitPriceCents: item.product.priceCents,
                    quantity: item.quantity,
                    thumbnailURL: item.product.imageNames.first,
                    selectedColorId: item.selectedColor?.id,
                    selectedColorName: item.selectedColor?.name,
                    selectedColorHex: item.selectedColor?.hex,
                    productionPreviewURL: nil
                )
            }
        )
    }

    private func derivedOrderStatus(
        from shipments: [Shipment],
        current: OrderStatus
    ) -> OrderStatus {
        guard !shipments.isEmpty else { return current }

        let cancelledCount = shipments.filter { $0.status == .cancelled }.count
        if cancelledCount == shipments.count {
            return .cancelled
        }

        let active = shipments.filter { $0.status != .cancelled }
        if active.isEmpty {
            return .cancelled
        }

        let activeDelivered = active.filter { $0.status == .delivered }.count
        let activeShipped = active.filter { $0.status == .shipped }.count
        let activePreparing = active.filter { $0.status == .preparing }.count

        if activeDelivered == active.count {
            return .delivered
        }

        if activeShipped + activeDelivered == active.count, activeShipped > 0 {
            return .shipped
        }

        if activeShipped > 0 && activePreparing > 0 {
            return .partiallyShipped
        }

        if activePreparing > 0 {
            return .processing
        }

        return current
    }

    @discardableResult
    func createSupportRequest(
        orderId: String,
        type: OrderSupportRequestType,
        sellerId: String,
        shipmentId: String,
        reason: String,
        reasonCode: String? = nil
    ) async -> String? {
        orderSupportError = nil
        do {
            let updated = try await OrdersAPI.createSupportRequest(
                orderId: orderId,
                type: type,
                sellerId: sellerId,
                shipmentId: shipmentId,
                reason: reason,
                reasonCode: reasonCode
            )
            upsertOrder(updated)
            return updated.supportRequests
                .filter { $0.type == type && $0.sellerId == sellerId && $0.status == .pending }
                .max(by: { $0.createdAt < $1.createdAt })?.id
        } catch {
            orderSupportError = error.localizedDescription
            return nil
        }
    }

    func updateSupportRequest(
        orderId: String,
        requestId: String,
        status: OrderSupportRequestStatus,
        resolutionNote: String? = nil
    ) async {
        orderSupportError = nil
        do {
            let updated = try await OrdersAPI.updateSupportRequest(
                orderId: orderId,
                requestId: requestId,
                status: status,
                resolutionNote: resolutionNote
            )
            upsertOrder(updated)
        } catch {
            orderSupportError = error.localizedDescription
        }
    }

    func fetchSupportThread(orderId: String, sellerId: String) async -> [OrderSupportMessage] {
        orderSupportError = nil
        let localMessages = localSupportMessages(orderId: orderId, sellerId: sellerId)

        guard MarketplaceAuthSession.hasAuthenticatedSession else {
            orderSupportError = messagingAuthHint
            return localMessages
        }

        await MarketplaceAuthSession.syncAfterIdentityChange()

        guard MarketplaceAuthSession.hasAuthenticatedSession else {
            orderSupportError = messagingAuthHint
            return localMessages
        }

        do {
            return try await OrdersAPI.fetchSupportThread(orderId: orderId, sellerId: sellerId)
        } catch {
            orderSupportError = APIErrorMessage.userFacing(error)
            return localMessages
        }
    }

    func sendSupportMessage(orderId: String, sellerId: String, text: String, senderName: String? = nil) async -> [OrderSupportMessage] {
        orderSupportError = nil

        guard MarketplaceAuthSession.hasAuthenticatedSession else {
            orderSupportError = messagingAuthHint
            return localSupportMessages(orderId: orderId, sellerId: sellerId)
        }

        await MarketplaceAuthSession.syncAfterIdentityChange()

        do {
            let response = try await OrdersAPI.sendSupportMessage(
                orderId: orderId,
                sellerId: sellerId,
                text: text,
                senderName: senderName
            )
            if let order = response.order {
                upsertOrder(order)
            }
            return response.messages
        } catch {
            orderSupportError = APIErrorMessage.userFacing(error)
            return localSupportMessages(orderId: orderId, sellerId: sellerId)
        }
    }

    private var messagingAuthHint: String {
        let role = UserDefaults.standard.string(forKey: "userRole") ?? ""
        if role == "seller" {
            return "Sign in as your seller account to send and receive order messages."
        }
        return "Sign in with your buyer account to send and receive order messages."
    }

    private func localSupportMessages(orderId: String, sellerId: String) -> [OrderSupportMessage] {
        guard let order = order(withId: orderId) else { return [] }
        return order.orderMessages
            .filter { $0.sellerId == sellerId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func persist() {
        LocalCodableStore.save(orders, key: storageKey)
    }

    private func mergeServerOrders(_ serverOrders: [Order]) {
        let previousById = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })
        var mergedById = Dictionary(uniqueKeysWithValues: serverOrders.map { ($0.id, $0) })
        for localOrder in orders where mergedById[localOrder.id] == nil {
            mergedById[localOrder.id] = localOrder
        }

        orders = mergedById.values.sorted { $0.createdAt > $1.createdAt }
        persist()

        for order in serverOrders {
            emitEventsIfNeeded(for: order, previous: previousById[order.id])
        }
    }

    private func upsertOrder(_ order: Order) {
        let previousOrder = orders.first(where: { $0.id == order.id })
        if let existingIndex = orders.firstIndex(where: { $0.id == order.id }) {
            orders[existingIndex] = order
        } else {
            orders.insert(order, at: 0)
        }

        orders.sort { $0.createdAt > $1.createdAt }
        persist()
        emitEventsIfNeeded(for: order, previous: previousOrder)
    }

    private func emitEventsIfNeeded(for order: Order, previous: Order?) {
        // Use Optional.map — do not call flatMap on String (that iterates Characters).
        let buyerIdentity = order.buyerEmail
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap { $0.isEmpty ? nil : "buyer:\($0)" }

        if previous == nil {
            let lineItems = order.shipments.flatMap(\.items)
            let trimmedFirst = lineItems.first?.productName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let firstProductName = trimmedFirst.isEmpty ? "your order" : trimmedFirst
            let hasMakerVideo = lineItems.contains { line in
                guard let s = line.productionPreviewURL?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
                return !s.isEmpty
            }
            eventStore.record(
                CommerceEvent(
                    kind: .orderPlaced,
                    buyerIdentity: buyerIdentity,
                    orderId: order.id,
                    metadata: [
                        "sellerCount": "\(order.shipments.count)",
                        "itemCount": "\(order.totalItemsCount)",
                        "firstProductName": firstProductName,
                        "hasMakerVideo": hasMakerVideo ? "1" : "0"
                    ]
                )
            )
        }

        if previous != nil, previous?.status != order.status {
            eventStore.record(
                CommerceEvent(
                    kind: .orderStatusUpdated,
                    buyerIdentity: buyerIdentity,
                    orderId: order.id,
                    sellerId: order.shipments.first?.sellerId,
                    metadata: [
                        "status": order.status.rawValue
                    ]
                )
            )
        }

        let previousShipmentsByID = Dictionary(uniqueKeysWithValues: (previous?.shipments ?? []).map { ($0.id, $0) })
        for shipment in order.shipments {
            let previousShipment = previousShipmentsByID[shipment.id]
            guard previous != nil else { continue }
            guard previousShipment?.status != shipment.status else { continue }

            eventStore.record(
                CommerceEvent(
                    kind: .shipmentStatusUpdated,
                    buyerIdentity: buyerIdentity,
                    productId: shipment.items.first?.productId,
                    orderId: order.id,
                    shipmentId: shipment.id,
                    sellerId: shipment.sellerId,
                    metadata: [
                        "shipmentStatus": shipment.status.rawValue,
                        "productName": shipment.items.first?.productName ?? "your item",
                        "carrier": shipment.carrier ?? "",
                        "trackingNumber": shipment.trackingNumber ?? "",
                        "buyerUserId": buyerIdentity ?? ""
                    ]
                )
            )
        }

        emitSupportEventsIfNeeded(for: order, previous: previous)
    }

    private func emitSupportEventsIfNeeded(for order: Order, previous: Order?) {
        guard previous != nil else { return }

        let buyerIdentity = order.buyerEmail
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap { $0.isEmpty ? nil : "buyer:\($0)" }

        let previousRequests = Dictionary(uniqueKeysWithValues: (previous?.supportRequests ?? []).map { ($0.id, $0) })
        for request in order.supportRequests {
            let prior = previousRequests[request.id]
            if prior == nil {
                eventStore.record(
                    CommerceEvent(
                        kind: .orderSupportRequestCreated,
                        buyerIdentity: buyerIdentity,
                        orderId: order.id,
                        sellerId: request.sellerId,
                        metadata: [
                            "requestId": request.id,
                            "requestType": request.type.rawValue,
                            "requestStatus": request.status.rawValue,
                            "requestedBy": request.requestedBy,
                            "reason": request.reason
                        ]
                    )
                )
            } else if prior?.status != request.status {
                eventStore.record(
                    CommerceEvent(
                        kind: .orderSupportRequestUpdated,
                        buyerIdentity: buyerIdentity,
                        orderId: order.id,
                        sellerId: request.sellerId,
                        metadata: [
                            "requestId": request.id,
                            "requestType": request.type.rawValue,
                            "requestStatus": request.status.rawValue,
                            "requestedBy": request.requestedBy,
                            "resolutionNote": request.resolutionNote ?? ""
                        ]
                    )
                )
            }
        }

        let previousMessageIDs = Set(previous?.orderMessages.map(\.id) ?? [])
        for message in order.orderMessages where !previousMessageIDs.contains(message.id) {
            eventStore.record(
                CommerceEvent(
                    kind: .orderSupportMessageSent,
                    buyerIdentity: buyerIdentity,
                    orderId: order.id,
                    sellerId: message.sellerId,
                    metadata: [
                        "messageId": message.id,
                        "senderRole": message.senderRole,
                        "text": message.text
                    ]
                )
            )
        }
    }
}
