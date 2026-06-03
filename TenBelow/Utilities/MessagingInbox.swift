import Foundation

enum MessagingThreadKind: Hashable {
    case shopInquiry(sellerId: String)
    case order(orderId: String, sellerId: String)
}

/// Unified inbox row for shop inquiries and order support threads.
struct MessagingInboxEntry: Identifiable, Hashable {
    let kind: MessagingThreadKind
    let sellerId: String
    let sellerName: String
    /// Set for seller-side shop chats (which buyer the thread is with).
    let inquiryBuyerEmail: String?
    let buyerLabel: String
    let contextLabel: String
    let lastMessageText: String
    let lastMessageTimestamp: String
    let lastMessageDate: Date

    var id: String {
        switch kind {
        case .shopInquiry(let sellerId):
            return "inquiry|\(sellerId)"
        case .order(let orderId, let sellerId):
            return "order|\(orderId)|\(sellerId)"
        }
    }

    var isShopInquiry: Bool {
        if case .shopInquiry = kind { return true }
        return false
    }
}

enum MessagingInbox {
    static func buyerEntries(
        orders: [Order],
        inquiryThreads: [SellerInquiryThread],
        sellerProfiles: [SellerProfile],
        storefrontProducts: [Product]
    ) -> [MessagingInboxEntry] {
        var entries: [MessagingInboxEntry] = []

        for thread in inquiryThreads {
            guard let sellerName = resolveSellerName(
                sellerId: thread.sellerId,
                sellerProfiles: sellerProfiles,
                storefrontProducts: storefrontProducts
            ) else { continue }

            let last = thread.lastMessage
            entries.append(
                MessagingInboxEntry(
                    kind: .shopInquiry(sellerId: thread.sellerId),
                    sellerId: thread.sellerId,
                    sellerName: sellerName,
                    inquiryBuyerEmail: nil,
                    buyerLabel: "You",
                    contextLabel: "Shop chat",
                    lastMessageText: last?.text ?? "Ask about products, shipping, or custom work.",
                    lastMessageTimestamp: last?.timestampLabel ?? thread.updatedAt.formatted(date: .abbreviated, time: .omitted),
                    lastMessageDate: last?.createdAt ?? thread.updatedAt
                )
            )
        }

        for orderRef in OrderSupportThreads.buyerThreads(
            from: orders,
            sellerProfiles: sellerProfiles,
            storefrontProducts: storefrontProducts
        ) {
            entries.append(
                MessagingInboxEntry(
                    kind: .order(orderId: orderRef.orderId, sellerId: orderRef.sellerId),
                    sellerId: orderRef.sellerId,
                    sellerName: orderRef.sellerName,
                    inquiryBuyerEmail: nil,
                    buyerLabel: orderRef.buyerLabel,
                    contextLabel: "Order \(orderRef.orderId)",
                    lastMessageText: orderRef.lastMessageText,
                    lastMessageTimestamp: orderRef.lastMessageTimestamp,
                    lastMessageDate: orderRef.lastMessageDate
                )
            )
        }

        return entries.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    static func sellerEntries(
        orders: [Order],
        inquiryThreads: [SellerInquiryThread],
        sellerId: String
    ) -> [MessagingInboxEntry] {
        var entries: [MessagingInboxEntry] = []
        let normalizedSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)

        for thread in inquiryThreads where thread.sellerId == normalizedSellerId {
            let last = thread.lastMessage
            let buyerLabel = formattedBuyerLabel(thread.buyerName, email: thread.buyerEmail)
            entries.append(
                MessagingInboxEntry(
                    kind: .shopInquiry(sellerId: thread.sellerId),
                    sellerId: thread.sellerId,
                    sellerName: normalizedSellerId,
                    inquiryBuyerEmail: thread.buyerEmail,
                    buyerLabel: buyerLabel,
                    contextLabel: "Shop chat",
                    lastMessageText: last?.text ?? "Buyer question from your storefront.",
                    lastMessageTimestamp: last?.timestampLabel ?? thread.updatedAt.formatted(date: .abbreviated, time: .omitted),
                    lastMessageDate: last?.createdAt ?? thread.updatedAt
                )
            )
        }

        for orderRef in OrderSupportThreads.sellerThreads(from: orders, sellerId: normalizedSellerId) {
            entries.append(
                MessagingInboxEntry(
                    kind: .order(orderId: orderRef.orderId, sellerId: orderRef.sellerId),
                    sellerId: orderRef.sellerId,
                    sellerName: orderRef.sellerName,
                    inquiryBuyerEmail: nil,
                    buyerLabel: orderRef.buyerLabel,
                    contextLabel: "Order \(orderRef.orderId)",
                    lastMessageText: orderRef.lastMessageText,
                    lastMessageTimestamp: orderRef.lastMessageTimestamp,
                    lastMessageDate: orderRef.lastMessageDate
                )
            )
        }

        return entries.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    static func buyerShopEntry(
        for sellerId: String,
        sellerName: String,
        existingThread: SellerInquiryThread?
    ) -> MessagingInboxEntry {
        let last = existingThread?.lastMessage
        return MessagingInboxEntry(
            kind: .shopInquiry(sellerId: sellerId),
            sellerId: sellerId,
            sellerName: sellerName,
            inquiryBuyerEmail: nil,
            buyerLabel: "You",
            contextLabel: "Shop chat",
            lastMessageText: last?.text ?? "Ask about products, shipping, or custom work.",
            lastMessageTimestamp: last?.timestampLabel ?? "",
            lastMessageDate: last?.createdAt ?? .distantPast
        )
    }

    private static func resolveSellerName(
        sellerId: String,
        sellerProfiles: [SellerProfile],
        storefrontProducts: [Product]
    ) -> String? {
        if let profile = resolvedSellerProfile(
            sellerId: sellerId,
            storefrontProducts: storefrontProducts.filter { $0.sellerId == sellerId },
            remoteProfiles: sellerProfiles
        ) {
            return profile.displayName
        }
        return sellerId.isEmpty ? nil : sellerId
    }

    private static func formattedBuyerLabel(_ name: String?, email: String) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty { return trimmedName }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmail.isEmpty ? "Buyer" : trimmedEmail
    }
}
