import Foundation

enum OrdersMode: String, CaseIterable, Identifiable {
    case buyer = "My Orders"
    case seller = "Manage Orders"
    var id: String { rawValue }
}

enum OrderStatus: String, Codable {
    case placed
    case processing
    case partiallyShipped
    case shipped
    case delivered
}

enum ShipmentStatus: String, Codable {
    case preparing
    case shipped
    case delivered
}

struct Order: Identifiable, Codable, Hashable {
    let id: String
    var createdAt: Date
    var status: OrderStatus

    var buyerEmail: String?
    var shipToCity: String?
    var shipToState: String?

    var currency: String
    var totalCents: Int

    var shipments: [Shipment]

    var totalItemsCount: Int {
        shipments.reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.quantity } }
    }
}

struct Shipment: Identifiable, Codable, Hashable {
    let id: String
    var sellerId: String
    var sellerName: String
    var sellerHandle: String?
    var status: ShipmentStatus

    var shipByDate: Date?
    var carrier: String?
    var trackingNumber: String?
    var shippedAt: Date?
    var deliveredAt: Date?

    var items: [OrderLineItem]
}

struct OrderLineItem: Identifiable, Codable, Hashable {
    let id: String
    var productId: String
    var productName: String
    var unitPriceCents: Int
    var quantity: Int
    var thumbnailURL: String?
    /// Optional order-bound production clip URL string.
    /// This is independent from public product media/gallery.
    var productionPreviewURL: String? = nil

    var productionPreviewResolvedURL: URL? {
        guard let productionPreviewURL,
              let url = URL(string: productionPreviewURL)
        else { return nil }
        return url
    }
}
