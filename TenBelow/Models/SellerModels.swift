import Foundation

struct CreateSellerRequest: Codable {
    let sellerId: String
    let email: String
    let businessName: String?
}

struct CreateSellerResponse: Codable {
    let sellerId: String
    let stripeAccountId: String
    let onboardingUrl: String
}

struct SellerStatusResponse: Codable {
    let sellerId: String
    let stripeAccountId: String
    let chargesEnabled: Bool
    let payoutsEnabled: Bool
    let detailsSubmitted: Bool
    let onboardingComplete: Bool
}

struct OnboardingLinkResponse: Codable {
    let sellerId: String
    let onboardingUrl: String
}

struct DashboardLinkResponse: Codable {
    let sellerId: String
    let dashboardUrl: String
}
