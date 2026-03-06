import Foundation

enum AppConstants {

    // MARK: - Shipping

    static let freeShippingThresholdCents = 2000
    static let flatShippingCents          = 499
    static let minimumOrderCents          = 2000

    // MARK: - Remote URLs (replace with your hosted URLs)

    static let catalogURL = URL(string: "https://your-server.com/api/products.json")!
    static let configURL  = URL(string: "https://your-server.com/api/config.json")!

    // MARK: - Cache File Names

    static let catalogCacheFile = "products_cache.json"
    static let configCacheFile  = "config_cache.json"

    // MARK: - Bundle Fallback File Names

    static let catalogFallbackFile = "products_fallback"
    static let configFallbackFile  = "config_fallback"

    // MARK: - Marketplace / Reporting

    static let reportListingEmail = "report@tenbelow.com"

    // MARK: - Legal (replace with your URLs)

    static let termsURL           = URL(string: "https://tenbelow.com/terms")!
    static let privacyPolicyURL   = URL(string: "https://tenbelow.com/privacy")!
    static let refundPolicyURL    = URL(string: "https://tenbelow.com/refunds")!
    static let ipPolicyURL        = URL(string: "https://tenbelow.com/ip-policy")!
    static let dmcaURL            = URL(string: "https://tenbelow.com/dmca")!
    static let sellerAgreementURL = URL(string: "https://tenbelow.com/seller-agreement")!

    // MARK: - Stripe (replace with your publishable key from dashboard.stripe.com)

    static let stripePublishableKey = "pk_test_YOUR_PUBLISHABLE_KEY"
}

