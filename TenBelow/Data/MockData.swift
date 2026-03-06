//
//  MockData.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import Foundation

enum MockData {

    // MARK: - Products

    static let products: [Product] = [
        Product(
            id: "cable-clip-01",
            sellerId: "seller_001",
            name: "Desk Cable Clip",
            priceCents: 500,
            category: .desk,
            imageNames: ["sample1"],
            demoVideoURL: nil,
            material: "PLA+",
            durabilityNote: "Built for everyday indoor use.",
            careWarnings: ["Avoid heat (car dashboards / dishwashers).", "Not load-bearing."],
            shipsInDays: 2...4
        ),
        Product(
            id: "cup-holder-01",
            sellerId: "seller_002",
            name: "Cup Holder Insert",
            priceCents: 700,
            category: .car,
            imageNames: ["sample2"],
            demoVideoURL: nil,
            material: "PETG",
            durabilityNote: "Tougher material, better for warm environments.",
            careWarnings: ["Still avoid extreme heat.", "Hand clean only."],
            shipsInDays: 2...4
        ),
        Product(
            id: "headphone-hook-01",
            sellerId: "seller_001",
            name: "Headphone Hook",
            priceCents: 600,
            category: .desk,
            imageNames: ["sample1"],
            demoVideoURL: nil,
            material: "PLA+",
            durabilityNote: "Clips onto most desks up to 1.5\" thick.",
            careWarnings: ["Not for headphones over 400g.", "Indoor use only."],
            shipsInDays: 2...4
        ),
        Product(
            id: "plant-pot-01",
            sellerId: "seller_001",
            name: "Mini Geometric Planter",
            priceCents: 800,
            category: .home,
            imageNames: ["sample2"],
            demoVideoURL: nil,
            material: "PLA+",
            durabilityNote: "Great for succulents and small plants.",
            careWarnings: ["Not waterproof — use a liner.", "Indoor use only."],
            shipsInDays: 3...5
        ),
        Product(
            id: "phone-stand-01",
            sellerId: "seller_002",
            name: "Phone Stand",
            priceCents: 500,
            category: .tech,
            imageNames: ["sample1"],
            demoVideoURL: nil,
            material: "PLA+",
            durabilityNote: "Fits most phones with or without case.",
            careWarnings: ["Don't force oversized devices.", "Keep away from heat."],
            shipsInDays: 2...4
        ),
        Product(
            id: "coaster-set-01",
            sellerId: "seller_001",
            name: "Hex Coaster Set (4)",
            priceCents: 999,
            category: .home,
            imageNames: ["sample2"],
            demoVideoURL: nil,
            material: "PETG",
            durabilityNote: "Heat-resistant up to 80°C.",
            careWarnings: ["Hand wash only.", "May leave marks on glass tables."],
            shipsInDays: 3...5
        ),
        Product(
            id: "car-vent-clip-01",
            sellerId: "seller_002",
            name: "Car Vent Phone Clip",
            priceCents: 650,
            category: .car,
            imageNames: ["sample1"],
            demoVideoURL: nil,
            material: "PETG",
            durabilityNote: "Snaps onto standard car vents.",
            careWarnings: ["Not for round vents.", "May mark soft-touch interiors."],
            shipsInDays: 2...4
        ),
        Product(
            id: "bookmark-01",
            sellerId: "seller_001",
            name: "Page-Hugger Bookmark",
            priceCents: 300,
            category: .gifts,
            imageNames: ["sample2"],
            demoVideoURL: nil,
            material: "PLA+",
            durabilityNote: "Flexible clip that hugs pages.",
            careWarnings: ["May mark thin pages.", "Keep away from pets."],
            shipsInDays: 2...3
        ),
        Product(
            id: "mystery-gadget-01",
            sellerId: "seller_001",
            name: "Mystery Desk Gadget",
            priceCents: 400,
            category: .didntKnow,
            imageNames: ["sample1"],
            demoVideoURL: nil,
            material: "PLA+",
            durabilityNote: "A fun desk fidget you didn't know you needed.",
            careWarnings: ["Decorative only.", "Not a toy for small children."],
            shipsInDays: 2...4
        ),
        Product(
            id: "cable-organizer-01",
            sellerId: "seller_002",
            name: "Cable Spine Organizer",
            priceCents: 850,
            category: .tech,
            imageNames: ["sample2"],
            demoVideoURL: nil,
            material: "PLA+",
            durabilityNote: "Routes up to 6 cables neatly.",
            careWarnings: ["Not for cables thicker than 8mm.", "Mount with included adhesive."],
            shipsInDays: 3...5
        )
    ]

    // MARK: - Current Drop

    static let currentDrop = Drop(
        id: "drop-jan-2026",
        title: "January Lamp Drop",
        subtitle: "Limited • USB Powered • Warm Glow",
        tagline: "A handmade desk lamp printed in translucent PETG — warm, minimal, and yours.",
        daysRemaining: 6,
        products: [
            Product(
                id: "lamp-drop-01",
                sellerId: "seller_001",
                name: "Cloud Lamp — Warm White",
                priceCents: 999,
                category: .home,
                imageNames: ["sample1"],
                demoVideoURL: nil,
                material: "PETG (translucent)",
                durabilityNote: "USB powered, fits any desk. Warm LED included.",
                careWarnings: ["Do not submerge.", "LED is not replaceable.", "Indoor use only."],
                shipsInDays: 5...7
            ),
            Product(
                id: "lamp-drop-02",
                sellerId: "seller_001",
                name: "Cloud Lamp — Cool Blue",
                priceCents: 999,
                category: .home,
                imageNames: ["sample2"],
                demoVideoURL: nil,
                material: "PETG (translucent)",
                durabilityNote: "USB powered, fits any desk. Cool LED included.",
                careWarnings: ["Do not submerge.", "LED is not replaceable.", "Indoor use only."],
                shipsInDays: 5...7
            )
        ],
        imageName: "sample1"
    )

    // MARK: - Mock Orders

    static let orders: [Order] = [
        Order(
            id: "ORD-1001",
            createdAt: Calendar.current.date(byAdding: .day, value: -12, to: .now)!,
            status: .delivered,
            buyerEmail: "steven@example.com",
            shipToCity: "Austin",
            shipToState: "TX",
            currency: "USD",
            totalCents: 1999,
            shipments: [
                Shipment(
                    id: "SHP-2001",
                    sellerId: "seller_001",
                    sellerName: "PrintLab",
                    sellerHandle: "@printlab",
                    status: .delivered,
                    carrier: "USPS",
                    trackingNumber: "9400111899223456789012",
                    shippedAt: Calendar.current.date(byAdding: .day, value: -10, to: .now),
                    deliveredAt: Calendar.current.date(byAdding: .day, value: -8, to: .now),
                    items: [
                        OrderLineItem(id: "LI-3001", productId: "cable-clip-01", productName: "Desk Cable Clip", unitPriceCents: 500, quantity: 2),
                        OrderLineItem(id: "LI-3002", productId: "coaster-set-01", productName: "Hex Coaster Set (4)", unitPriceCents: 999, quantity: 1)
                    ]
                )
            ]
        ),
        Order(
            id: "ORD-1002",
            createdAt: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            status: .partiallyShipped,
            buyerEmail: "steven@example.com",
            shipToCity: "Austin",
            shipToState: "TX",
            currency: "USD",
            totalCents: 1850,
            shipments: [
                Shipment(
                    id: "SHP-2002",
                    sellerId: "seller_001",
                    sellerName: "PrintLab",
                    sellerHandle: "@printlab",
                    status: .shipped,
                    carrier: "UPS",
                    trackingNumber: "1Z999AA10123456784",
                    shippedAt: Calendar.current.date(byAdding: .day, value: -1, to: .now),
                    items: [
                        OrderLineItem(id: "LI-3003", productId: "headphone-hook-01", productName: "Headphone Hook", unitPriceCents: 600, quantity: 1)
                    ]
                ),
                Shipment(
                    id: "SHP-2003",
                    sellerId: "seller_002",
                    sellerName: "MakerBox",
                    sellerHandle: "@makerbox",
                    status: .preparing,
                    items: [
                        OrderLineItem(id: "LI-3004", productId: "cup-holder-01", productName: "Cup Holder Insert", unitPriceCents: 700, quantity: 1),
                        OrderLineItem(id: "LI-3005", productId: "phone-stand-01", productName: "Phone Stand", unitPriceCents: 550, quantity: 1)
                    ]
                )
            ]
        ),
        Order(
            id: "ORD-1003",
            createdAt: .now,
            status: .placed,
            buyerEmail: "steven@example.com",
            shipToCity: "Austin",
            shipToState: "TX",
            currency: "USD",
            totalCents: 999,
            shipments: [
                Shipment(
                    id: "SHP-2004",
                    sellerId: "seller_001",
                    sellerName: "PrintLab",
                    sellerHandle: "@printlab",
                    status: .preparing,
                    items: [
                        OrderLineItem(id: "LI-3006", productId: "lamp-drop-01", productName: "Cloud Lamp — Warm White", unitPriceCents: 999, quantity: 1)
                    ]
                )
            ]
        )
    ]

    // MARK: - Helpers

    static func products(for category: Category) -> [Product] {
        products.filter { $0.category == category }
    }
}
