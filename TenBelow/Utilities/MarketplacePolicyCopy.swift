import Foundation

/// Shared marketplace policy language for buyer UI, seller settings, and legal alignment.
enum MarketplacePolicyCopy {
    static let defaultSellerPolicyNote =
        "Made-to-order pieces may vary slightly in finish. Every order is checked before it ships."

    static let platformStandardsTitle = "How TenBelow handles orders"

    static let platformStandardsBody = """
Made-to-order sales are final unless a qualifying issue is reported with photo proof. Buyers may request one exchange per item within seven days of delivery for damage, defect, wrong item, or material flaw. Refunds are not standard—sellers choose whether to accept one damage-based refund request per shipment.
"""

    static let buyerOrderSupportIntro =
        "Message each seller directly. Cancellation and refund options follow their shop settings and TenBelow order rules."

    static let buyerExchangeIntro =
        "Made-to-order items are not returnable. If something arrives damaged, defective, wrong, or materially flawed, you may request one exchange per item with photo proof."

    static let buyerExchangeAfterDelivery =
        "Available after the carrier marks your order delivered."

    static let buyerExchangeUsed =
        "This order has already used its one-time exchange."

    static let buyerExchangeUnavailable =
        "Exchange eligibility is not available for this order right now."

    static let buyerRefundIntro =
        "One request per shipment. Choose what went wrong, describe the issue, and attach at least one clear photo. The seller reviews every request."

    static let buyerCancelNotGuaranteedTitle = "Cancellation is not guaranteed"

    static func buyerCancelNotGuaranteedBody(sellerName: String) -> String {
        "\(sellerName) must approve before anything is cancelled. If production has already started, the request may be declined."
    }

    static let sellerPoliciesSubtitle =
        "Set the post-purchase rules shoppers see on your shop. TenBelow handles exchanges platform-wide; you control cancellations and optional refunds."

    static let sellerAcceptReturnsSubtitle =
        "Show buyers you accept post-delivery returns within your stated window."

    static let sellerAllowExchangesSubtitle =
        "Stay enrolled in TenBelow's one-time exchange process for qualifying issues."

    static let sellerAllowCancellationsSubtitle =
        "Let buyers request cancellation while the shipment is still preparing."

    static let sellerAllowRefundsSubtitle =
        "Optional. One damage-based refund request per shipment, with required photo proof."

    static let sellerPolicyNotePrompt = defaultSellerPolicyNote

    static let sellerPolicyNoteFieldTitle = "Shop note"

    static let exchangePolicyLinkTitle = "Exchange policy"

    static let readExchangePolicyButton = "Read exchange policy"
}
