import Foundation

/// One buyer↔seller conversation tied to a specific order (server-backed `orderMessages`).
struct OrderSupportThreadRef: Identifiable, Hashable {
    let orderId: String
    let sellerId: String
    let sellerName: String
    let buyerLabel: String
    let lastMessageText: String
    let lastMessageTimestamp: String
    let lastMessageDate: Date
    let hasMessages: Bool

    var id: String { "\(orderId)|\(sellerId)" }
}

enum OrderSupportThreads {
    /// Buyer threads: one per seller on each order (newest activity first).
    static func buyerThreads(
        from orders: [Order],
        sellerProfiles: [SellerProfile],
        storefrontProducts: [Product]
    ) -> [OrderSupportThreadRef] {
        var refs: [OrderSupportThreadRef] = []

        for order in orders {
            let sellerIds = Set(order.shipments.map(\.sellerId))
            for sellerId in sellerIds {
                guard let sellerName = resolveSellerName(
                    sellerId: sellerId,
                    order: order,
                    sellerProfiles: sellerProfiles,
                    storefrontProducts: storefrontProducts
                ) else { continue }

                let messages = order.orderMessages
                    .filter { $0.sellerId == sellerId }
                    .sorted { $0.createdAt < $1.createdAt }

                let last = messages.last
                refs.append(
                    OrderSupportThreadRef(
                        orderId: order.id,
                        sellerId: sellerId,
                        sellerName: sellerName,
                        buyerLabel: order.buyerEmail ?? "You",
                        lastMessageText: last?.text ?? "No messages yet — tap to ask about this order.",
                        lastMessageTimestamp: last?.timestampLabel ?? order.createdAt.formatted(date: .abbreviated, time: .omitted),
                        lastMessageDate: last?.createdAt ?? order.createdAt,
                        hasMessages: !messages.isEmpty
                    )
                )
            }
        }

        return refs.sorted { lhs, rhs in
            if lhs.lastMessageDate != rhs.lastMessageDate {
                return lhs.lastMessageDate > rhs.lastMessageDate
            }
            return lhs.orderId > rhs.orderId
        }
    }

    /// Seller threads: one row per order that includes this seller's shipment(s).
    static func sellerThreads(from orders: [Order], sellerId: String) -> [OrderSupportThreadRef] {
        let normalizedSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSellerId.isEmpty else { return [] }

        var refs: [OrderSupportThreadRef] = []

        for order in orders {
            guard order.shipments.contains(where: { $0.sellerId == normalizedSellerId }) else { continue }

            let sellerName = order.shipments.first(where: { $0.sellerId == normalizedSellerId })?.sellerName
                ?? normalizedSellerId

            let messages = order.orderMessages
                .filter { $0.sellerId == normalizedSellerId }
                .sorted { $0.createdAt < $1.createdAt }

            let last = messages.last
            let buyerLabel = formattedBuyerLabel(order.buyerEmail)

            refs.append(
                OrderSupportThreadRef(
                    orderId: order.id,
                    sellerId: normalizedSellerId,
                    sellerName: sellerName,
                    buyerLabel: buyerLabel,
                    lastMessageText: last?.text ?? "No messages yet — tap to reply about this order.",
                    lastMessageTimestamp: last?.timestampLabel ?? order.createdAt.formatted(date: .abbreviated, time: .omitted),
                    lastMessageDate: last?.createdAt ?? order.createdAt,
                    hasMessages: !messages.isEmpty
                )
            )
        }

        return refs.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    /// Most recent order that includes this seller (for storefront Message).
    static func preferredBuyerThread(
        for sellerId: String,
        orders: [Order],
        sellerProfiles: [SellerProfile],
        storefrontProducts: [Product]
    ) -> OrderSupportThreadRef? {
        buyerThreads(
            from: orders,
            sellerProfiles: sellerProfiles,
            storefrontProducts: storefrontProducts
        )
        .first(where: { $0.sellerId == sellerId })
    }

    /// Seller view: most recent order thread with a given buyer email.
    static func preferredSellerThread(
        buyerEmail: String,
        sellerId: String,
        orders: [Order]
    ) -> OrderSupportThreadRef? {
        let normalizedEmail = buyerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else { return nil }

        return sellerThreads(from: orders, sellerId: sellerId)
            .first { thread in
                guard let order = orders.first(where: { $0.id == thread.orderId }) else { return false }
                let orderEmail = order.buyerEmail?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() ?? ""
                return orderEmail == normalizedEmail
            }
    }

    static func threadCount(
        forSellerId sellerId: String,
        orders: [Order],
        sellerProfiles: [SellerProfile] = [],
        storefrontProducts: [Product] = []
    ) -> Int {
        buyerThreads(
            from: orders,
            sellerProfiles: sellerProfiles,
            storefrontProducts: storefrontProducts
        )
        .filter { $0.sellerId == sellerId }
        .count
    }

    private static func resolveSellerName(
        sellerId: String,
        order: Order,
        sellerProfiles: [SellerProfile],
        storefrontProducts: [Product]
    ) -> String? {
        if let fromShipment = order.shipments.first(where: { $0.sellerId == sellerId })?.sellerName,
           !fromShipment.isEmpty {
            return fromShipment
        }
        if let profile = resolvedSellerProfile(
            sellerId: sellerId,
            storefrontProducts: storefrontProducts.filter { $0.sellerId == sellerId },
            remoteProfiles: sellerProfiles
        ) {
            return profile.displayName
        }
        return sellerId.isEmpty ? nil : sellerId
    }

    private static func formattedBuyerLabel(_ email: String?) -> String {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Buyer" }
        return trimmed
    }
}
