import Foundation

struct SellerShippingQuote: Hashable {
    let sellerId: String
    let itemCount: Int
    let subtotalCents: Int
    let shippingCents: Int

    var isFree: Bool { shippingCents == 0 }

    var displayLabel: String {
        isFree ? "Free" : Money.format(cents: shippingCents)
    }
}

enum MarketplaceShippingCalculator {
    static let freeShippingThresholdCents = 3500

    static func shippingCents(itemCount: Int, subtotalCents: Int) -> Int {
        let count = max(0, itemCount)
        let subtotal = max(0, subtotalCents)
        guard count > 0, subtotal > 0 else { return 0 }
        if subtotal >= freeShippingThresholdCents { return 0 }
        switch count {
        case 1: return 599
        case 2: return 549
        case 3: return 499
        default: return 449
        }
    }

    static func quotes(for items: [CartItem]) -> [SellerShippingQuote] {
        let grouped = Dictionary(grouping: items, by: { $0.product.sellerId })
        return grouped.keys.sorted().map { sellerId in
            let sellerItems = grouped[sellerId] ?? []
            let itemCount = sellerItems.reduce(0) { $0 + $1.quantity }
            let subtotalCents = sellerItems.reduce(0) { $0 + ($1.product.priceCents * $1.quantity) }
            let shippingCents = shippingCents(itemCount: itemCount, subtotalCents: subtotalCents)
            return SellerShippingQuote(
                sellerId: sellerId,
                itemCount: itemCount,
                subtotalCents: subtotalCents,
                shippingCents: shippingCents
            )
        }
    }

    static func totalShippingCents(for items: [CartItem]) -> Int {
        quotes(for: items).reduce(0) { $0 + $1.shippingCents }
    }

    static func freeShippingRemainingCents(forSubtotal subtotalCents: Int) -> Int {
        max(freeShippingThresholdCents - max(0, subtotalCents), 0)
    }
}
