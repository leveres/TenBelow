import Foundation

enum AppConstants {
    private static let backendBaseURLInfoKey = "TENBELOW_BACKEND_BASE_URL"
    private static let stripePublishableKeyInfoKey = "TENBELOW_STRIPE_PUBLISHABLE_KEY"

    // MARK: - Shipping

    static let freeShippingThresholdCents = 2000
    static let flatShippingCents          = 499
    static let minimumOrderCents          = 2000

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

    // MARK: - Seller Subscription

    static let sellerSubscriptionProductID = "com.innovativecodeworks.com.TenBelow.seller.monthly"
    static let sellerSubscriptionFallbackPrice = "$11.99"
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    // MARK: - Stripe (replace with your publishable key from dashboard.stripe.com)

    static var backendBaseURL: URL? {
        let rawValue = configurationValue(for: backendBaseURLInfoKey)
        guard !rawValue.isEmpty,
              !isPlaceholderConfigurationValue(rawValue),
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }

        #if !DEBUG
        guard scheme == "https" else { return nil }
        if let host = url.host?.lowercased(),
           host == "localhost" || host == "127.0.0.1" {
            return nil
        }
        #endif

        return url
    }

    static var isBackendConfigured: Bool {
        backendBaseURL != nil
    }

    static var stripePublishableKey: String {
        let rawValue = configurationValue(for: stripePublishableKeyInfoKey)
        guard !rawValue.isEmpty, !isPlaceholderConfigurationValue(rawValue) else {
            return ""
        }
        return rawValue
    }

    static var isStripeConfigured: Bool {
        stripePublishableKey.hasPrefix("pk_")
    }

    static let stripeSetupMessage = "Checkout is turned off until Stripe is connected. Add your publishable key when you're ready to enable payments."

    static var checkoutSetupMessage: String {
        switch (isBackendConfigured, isStripeConfigured) {
        case (false, false):
            return "Checkout is unavailable until the backend URL and Stripe key are configured."
        case (false, true):
            return "Checkout is unavailable until the backend URL is configured."
        case (true, false):
            return stripeSetupMessage
        case (true, true):
            return ""
        }
    }

    private static func configurationValue(for key: String) -> String {
        String(Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPlaceholderConfigurationValue(_ value: String) -> Bool {
        let normalized = value.uppercased()
        return normalized.contains("YOUR_")
            || normalized.contains("PLACEHOLDER")
            || normalized.contains("REPLACE_ME")
    }
}

