import Foundation

struct CreateSellerRequest: Codable {
    let sellerId: String
    let email: String
    let businessName: String?
    let password: String?
    let legalName: String
    let shippingOriginCountry: String
    let shippingOriginState: String
    let sellerAgreementAccepted: Bool
    let sellerPoliciesAcknowledged: Bool
}

struct CreateSellerResponse: Codable {
    let sellerId: String
    let stripeAccountId: String
    let onboardingUrl: String
}

struct SellerMembershipSyncRequest: Codable {
    let sellerId: String
    let productId: String
    let isActive: Bool
    let expiresAt: String?
    let transactionId: String?
    let originalTransactionId: String?
}

struct SellerMembershipStatusResponse: Codable {
    let sellerId: String
    let requiresSubscription: Bool
    let hasActiveSubscription: Bool
    let productId: String
    let source: String
    let expiresAt: String?
    let lastSyncedAt: String?
}

struct CreateSellerMembershipCheckoutResponse: Codable {
    let url: String
}

struct SellerStatusResponse: Codable {
    let sellerId: String
    let stripeAccountId: String
    let chargesEnabled: Bool
    let payoutsEnabled: Bool
    let detailsSubmitted: Bool
    let onboardingComplete: Bool
    let completedSalesCount: Int
    let totalReviewCount: Int
    let positiveReviewCount: Int
    let averageRating: Double
    let activeDays: Int
    let trustedTesterVerified: Bool
    let hasActiveSubscription: Bool
    let subscriptionExpiresAt: String?
    let subscriptionProductId: String?

    enum CodingKeys: String, CodingKey {
        case sellerId, stripeAccountId
        case chargesEnabled, payoutsEnabled, detailsSubmitted, onboardingComplete
        case completedSalesCount, totalReviewCount, positiveReviewCount, averageRating, activeDays
        case trustedTesterVerified
        case hasActiveSubscription, subscriptionExpiresAt, subscriptionProductId
    }

    init(
        sellerId: String,
        stripeAccountId: String,
        chargesEnabled: Bool,
        payoutsEnabled: Bool,
        detailsSubmitted: Bool,
        onboardingComplete: Bool,
        completedSalesCount: Int = 0,
        totalReviewCount: Int = 0,
        positiveReviewCount: Int = 0,
        averageRating: Double = 0,
        activeDays: Int = 0,
        trustedTesterVerified: Bool = false,
        hasActiveSubscription: Bool = false,
        subscriptionExpiresAt: String? = nil,
        subscriptionProductId: String? = nil
    ) {
        self.sellerId = sellerId
        self.stripeAccountId = stripeAccountId
        self.chargesEnabled = chargesEnabled
        self.payoutsEnabled = payoutsEnabled
        self.detailsSubmitted = detailsSubmitted
        self.onboardingComplete = onboardingComplete
        self.completedSalesCount = completedSalesCount
        self.totalReviewCount = totalReviewCount
        self.positiveReviewCount = positiveReviewCount
        self.averageRating = averageRating
        self.activeDays = activeDays
        self.trustedTesterVerified = trustedTesterVerified
        self.hasActiveSubscription = hasActiveSubscription
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.subscriptionProductId = subscriptionProductId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sellerId = try c.decode(String.self, forKey: .sellerId)
        stripeAccountId = try c.decode(String.self, forKey: .stripeAccountId)
        chargesEnabled = try c.decode(Bool.self, forKey: .chargesEnabled)
        payoutsEnabled = try c.decode(Bool.self, forKey: .payoutsEnabled)
        detailsSubmitted = try c.decode(Bool.self, forKey: .detailsSubmitted)
        onboardingComplete = try c.decode(Bool.self, forKey: .onboardingComplete)
        completedSalesCount = try c.decodeIfPresent(Int.self, forKey: .completedSalesCount) ?? 0
        totalReviewCount = try c.decodeIfPresent(Int.self, forKey: .totalReviewCount) ?? 0
        positiveReviewCount = try c.decodeIfPresent(Int.self, forKey: .positiveReviewCount) ?? 0
        averageRating = try c.decodeIfPresent(Double.self, forKey: .averageRating) ?? 0
        activeDays = try c.decodeIfPresent(Int.self, forKey: .activeDays) ?? 0
        trustedTesterVerified = try c.decodeIfPresent(Bool.self, forKey: .trustedTesterVerified) ?? false
        hasActiveSubscription = try c.decodeIfPresent(Bool.self, forKey: .hasActiveSubscription) ?? false
        subscriptionExpiresAt = try c.decodeIfPresent(String.self, forKey: .subscriptionExpiresAt)
        subscriptionProductId = try c.decodeIfPresent(String.self, forKey: .subscriptionProductId)
    }
}

struct OnboardingLinkResponse: Codable {
    let sellerId: String
    let onboardingUrl: String
}

struct DashboardLinkResponse: Codable {
    let sellerId: String
    let dashboardUrl: String
}

struct SellerProfilesResponse: Codable {
    let sellers: [SellerProfile]
}

struct SellerProfileResponse: Codable {
    let seller: SellerProfile
}

struct UpdateSellerProfileRequest: Codable {
    let displayName: String
    let handle: String
    let bio: String
    let avatarURL: String?
    let bannerURL: String?
    let websiteURL: String?
    let location: String
    let materials: [String]
    let processingTime: String
    let shipsInMinDays: Int
    let shipsInMaxDays: Int
    let acceptsCustomOrders: Bool
    let customOrderInfoURL: String?
}

extension SellerStatusResponse {
    static func preview(sellerId: String) -> SellerStatusResponse {
        SellerStatusResponse(
            sellerId: sellerId,
            stripeAccountId: "acct_preview_\(sellerId)",
            chargesEnabled: false,
            payoutsEnabled: false,
            detailsSubmitted: false,
            onboardingComplete: false,
            completedSalesCount: 0,
            totalReviewCount: 0,
            positiveReviewCount: 0,
            averageRating: 0,
            activeDays: 0,
            trustedTesterVerified: false,
            hasActiveSubscription: false,
            subscriptionExpiresAt: nil,
            subscriptionProductId: AppConstants.sellerSubscriptionProductID
        )
    }

    var hasEarnedVerificationByPolicy: Bool {
        completedSalesCount >= SellerVerificationPolicy.minSuccessfulSales &&
        positiveReviewCount >= SellerVerificationPolicy.minPositiveReviews &&
        averageRating >= SellerVerificationPolicy.minAverageRating &&
        activeDays >= SellerVerificationPolicy.minActiveDays
    }

    var shouldShowVerifiedBadge: Bool {
        trustedTesterVerified || hasEarnedVerificationByPolicy
    }
}
