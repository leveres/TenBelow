import Foundation

enum SampleOrders {
    static var data: [Order] {
        let now = Date()
        return [
            Order(
                id: "ORD-1001",
                createdAt: now.addingTimeInterval(-86400 * 12),
                status: .partiallyShipped,
                buyerEmail: "buyer@email.com",
                shipToCity: "Philadelphia",
                shipToState: "PA",
                currency: "USD",
                totalCents: 2998,
                shipments: [
                    Shipment(
                        id: "SHP-2001",
                        sellerId: "SELL-01",
                        sellerName: "FilamentFox",
                        sellerHandle: "@filamentfox",
                        status: .shipped,
                        shipByDate: now.addingTimeInterval(86400 * 1),
                        carrier: "USPS",
                        trackingNumber: "9400 1234 5678",
                        shippedAt: now.addingTimeInterval(-86400 * 2),
                        deliveredAt: nil,
                        items: [
                            OrderLineItem(id: "LI-1", productId: "P-1", productName: "Desk Cable Clip", unitPriceCents: 500, quantity: 2, thumbnailURL: nil)
                        ]
                    ),
                    Shipment(
                        id: "SHP-2002",
                        sellerId: "SELL-02",
                        sellerName: "CloudCraft",
                        sellerHandle: "@cloudcraft",
                        status: .preparing,
                        shipByDate: now.addingTimeInterval(86400 * 2),
                        carrier: nil,
                        trackingNumber: nil,
                        shippedAt: nil,
                        deliveredAt: nil,
                        items: [
                            OrderLineItem(id: "LI-2", productId: "P-2", productName: "Cup Holder Insert", unitPriceCents: 700, quantity: 1, thumbnailURL: nil),
                            OrderLineItem(id: "LI-3", productId: "P-3", productName: "Hex Coaster Set (4)", unitPriceCents: 799, quantity: 1, thumbnailURL: nil)
                        ]
                    )
                ]
            ),
            Order(
                id: "ORD-1002",
                createdAt: now.addingTimeInterval(-86400 * 30),
                status: .delivered,
                buyerEmail: "buyer@email.com",
                shipToCity: "Philadelphia",
                shipToState: "PA",
                currency: "USD",
                totalCents: 999,
                shipments: [
                    Shipment(
                        id: "SHP-2003",
                        sellerId: "SELL-01",
                        sellerName: "FilamentFox",
                        sellerHandle: "@filamentfox",
                        status: .delivered,
                        shipByDate: now.addingTimeInterval(-86400 * 28),
                        carrier: "USPS",
                        trackingNumber: "9400 1111 2222 3333",
                        shippedAt: now.addingTimeInterval(-86400 * 26),
                        deliveredAt: now.addingTimeInterval(-86400 * 24),
                        items: [
                            OrderLineItem(id: "LI-4", productId: "P-4", productName: "Cloud Lamp — Warm White", unitPriceCents: 999, quantity: 1, thumbnailURL: nil)
                        ]
                    )
                ]
            ),
            Order(
                id: "ORD-1003",
                createdAt: now.addingTimeInterval(-86400 * 2),
                status: .placed,
                buyerEmail: "buyer@email.com",
                shipToCity: "Philadelphia",
                shipToState: "PA",
                currency: "USD",
                totalCents: 1200,
                shipments: [
                    Shipment(
                        id: "SHP-2004",
                        sellerId: "SELL-02",
                        sellerName: "CloudCraft",
                        sellerHandle: "@cloudcraft",
                        status: .preparing,
                        shipByDate: now.addingTimeInterval(86400 * 3),
                        carrier: nil,
                        trackingNumber: nil,
                        shippedAt: nil,
                        deliveredAt: nil,
                        items: [
                            OrderLineItem(id: "LI-5", productId: "P-5", productName: "Phone Stand", unitPriceCents: 600, quantity: 2, thumbnailURL: nil)
                        ]
                    )
                ]
            ),
            Order(
                id: "ORD-1004",
                createdAt: now.addingTimeInterval(-86400 * 1),
                status: .processing,
                buyerEmail: "customer@email.com",
                shipToCity: "Austin",
                shipToState: "TX",
                currency: "USD",
                totalCents: 1100,
                shipments: [
                    Shipment(
                        id: "SHP-2005",
                        sellerId: "seller_001",
                        sellerName: "PrintCraft Studio",
                        sellerHandle: "@printcraft",
                        status: .preparing,
                        shipByDate: now.addingTimeInterval(86400 * 2),
                        carrier: nil,
                        trackingNumber: nil,
                        shippedAt: nil,
                        deliveredAt: nil,
                        items: [
                            OrderLineItem(id: "LI-6", productId: "cable-clip-01", productName: "Desk Cable Clip", unitPriceCents: 500, quantity: 2, thumbnailURL: nil),
                            OrderLineItem(id: "LI-7", productId: "headphone-hook-01", productName: "Headphone Hook", unitPriceCents: 600, quantity: 1, thumbnailURL: nil)
                        ]
                    )
                ]
            )
        ]
    }
}
