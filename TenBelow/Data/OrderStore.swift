import Foundation
import Combine

enum SellerShipmentAction: String {
    case startProcessing
    case markShipped
    case markDelivered

    var buttonTitle: String {
        switch self {
        case .startProcessing:
            return "Start Production"
        case .markShipped:
            return "Mark Shipped"
        case .markDelivered:
            return "Mark Delivered"
        }
    }
}

@MainActor
final class OrderStore: ObservableObject {
    @Published private(set) var orders: [Order]
    @Published private(set) var isRefreshing = false
    @Published var refreshError: String?
    @Published var shipmentActionError: String?

    private let storageKey = "orderStore.orders"
    private let eventStore: CommerceEventStore

    init(eventStore: CommerceEventStore) {
        self.eventStore = eventStore
        orders = LocalCodableStore.load(
            key: storageKey,
            default: [Order]()
        )
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

        eventStore.record(
            CommerceEvent(
                kind: .orderPlaced,
                buyerIdentity: buyerIdentityKey,
                orderId: order.id,
                metadata: [
                    "sellerCount": "\(shipments.count)",
                    "itemCount": "\(order.totalItemsCount)"
                ]
            )
        )

        return order
    }

    func nextAction(for shipment: Shipment, order: Order) -> SellerShipmentAction? {
        switch shipment.status {
        case .delivered:
            return nil
        case .shipped:
            return .markDelivered
        case .preparing:
            return order.status == .placed ? .startProcessing : .markShipped
        }
    }

    func perform(
        _ action: SellerShipmentAction,
        orderId: String,
        shipmentId: String,
        sellerId: String
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
            orders[orderIndex].shipments[shipmentIndex].carrier = orders[orderIndex].shipments[shipmentIndex].carrier ?? "USPS"
            orders[orderIndex].shipments[shipmentIndex].trackingNumber = orders[orderIndex].shipments[shipmentIndex].trackingNumber ?? generatedTrackingNumber(from: shipmentId)
        case .markDelivered:
            orders[orderIndex].shipments[shipmentIndex].status = .delivered
            orders[orderIndex].shipments[shipmentIndex].deliveredAt = timestamp
        }

        orders[orderIndex].status = derivedOrderStatus(from: orders[orderIndex].shipments, current: orders[orderIndex].status)
        persist()

        eventStore.record(
            CommerceEvent(
                kind: .shipmentStatusUpdated,
                orderId: orderId,
                shipmentId: shipmentId,
                sellerId: sellerId,
                metadata: [
                    "action": action.rawValue,
                    "shipmentStatus": orders[orderIndex].shipments[shipmentIndex].status.rawValue
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
        sellerId: String
    ) async {
        shipmentActionError = nil
        do {
            let updatedOrder = try await OrdersAPI.performShipmentAction(
                action,
                orderId: orderId,
                shipmentId: shipmentId,
                sellerId: sellerId
            )
            upsertOrder(updatedOrder)
        } catch {
            perform(
                action,
                orderId: orderId,
                shipmentId: shipmentId,
                sellerId: sellerId
            )
            shipmentActionError = "Saved locally — will sync when connected."
        }
    }

    private var buyerIdentityKey: String {
        let userDefaults = UserDefaults.standard
        let email = userDefaults.string(forKey: "buyerEmail")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let email, !email.isEmpty {
            return "buyer:\(email)"
        }

        return "guest"
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
                    productionPreviewURL: item.product.productionPreviewURL?.absoluteString
                )
            }
        )
    }

    private func derivedOrderStatus(
        from shipments: [Shipment],
        current: OrderStatus
    ) -> OrderStatus {
        guard !shipments.isEmpty else { return current }

        let deliveredCount = shipments.filter { $0.status == .delivered }.count
        let shippedCount = shipments.filter { $0.status == .shipped }.count
        let preparingCount = shipments.filter { $0.status == .preparing }.count

        if deliveredCount == shipments.count {
            return .delivered
        }

        if shippedCount + deliveredCount == shipments.count, shippedCount > 0 {
            return .shipped
        }

        if shippedCount > 0 && preparingCount > 0 {
            return .partiallyShipped
        }

        if preparingCount > 0 {
            return .processing
        }

        return current
    }

    private func generatedTrackingNumber(from shipmentId: String) -> String {
        "TB-\(shipmentId.replacingOccurrences(of: "SHP-", with: ""))"
    }

    private func persist() {
        LocalCodableStore.save(orders, key: storageKey)
    }

    private func mergeServerOrders(_ serverOrders: [Order]) {
        var mergedById = Dictionary(uniqueKeysWithValues: serverOrders.map { ($0.id, $0) })
        for localOrder in orders where mergedById[localOrder.id] == nil {
            mergedById[localOrder.id] = localOrder
        }

        orders = mergedById.values.sorted { $0.createdAt > $1.createdAt }
        persist()
    }

    private func upsertOrder(_ order: Order) {
        if let existingIndex = orders.firstIndex(where: { $0.id == order.id }) {
            orders[existingIndex] = order
        } else {
            orders.insert(order, at: 0)
        }

        orders.sort { $0.createdAt > $1.createdAt }
        persist()
    }
}
