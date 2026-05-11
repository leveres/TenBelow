import Foundation

enum AppConstants {
    /// Injected via target build settings → `Info.plist` (`$(TENBELOW_*)`). For App Store Release, set HTTPS production URL, `pk_live_…`, and an app API key that matches the backend.
    private static let backendBaseURLInfoKey = "TENBELOW_BACKEND_BASE_URL"
    private static let stripePublishableKeyInfoKey = "TENBELOW_STRIPE_PUBLISHABLE_KEY"
    private nonisolated static let appAPIKeyInfoKey = "TENBELOW_APP_API_KEY"

    // MARK: - Shipping

    static let freeShippingThresholdCents = 1500
    static let flatShippingCents          = 499
    static let minimumOrderCents          = 1500

    // MARK: - Cache File Names

    static let catalogCacheFile = "products_cache.json"
    static let configCacheFile  = "config_cache.json"

    // MARK: - Bundle Fallback File Names

    static let catalogFallbackFile = "products_fallback"
    static let configFallbackFile  = "config_fallback"

    // MARK: - Marketplace / Reporting

    static let reportListingEmail = "report@tenbelow.com"

    /// Buyer support — exchange requests and general help (opens Mail via `mailto:`).
    static let supportEmail = "support@tenbelow.com"

    // MARK: - Legal (web mirrors)

    /// Optional public web mirrors. Buyer checkout/cart present Terms, Privacy, and Exchange in-app via `LegalDocumentSheet`.
    /// Keep these URLs accurate if any flow still loads them in a browser (for example seller IP policy).
    static let termsURL           = URL(string: "https://tenbelow.com/terms")!
    static let privacyPolicyURL   = URL(string: "https://tenbelow.com/privacy")!
    static let exchangePolicyURL  = URL(string: "https://tenbelow.com/exchanges")!
    static let ipPolicyURL        = URL(string: "https://tenbelow.com/ip-policy")!
    static let dmcaURL            = URL(string: "https://tenbelow.com/dmca")!
    static let sellerAgreementURL = URL(string: "https://tenbelow.com/seller-agreement")!

    // MARK: - Seller Subscription

    static let sellerSubscriptionProductID = "com.innovativecodeworks.com.TenBelow.seller.monthly"
    static let sellerSubscriptionFallbackPrice = "$11.99"
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    // MARK: - Stripe (replace with your publishable key from dashboard.stripe.com)

    static var backendBaseURL: URL? {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: debugBackendBaseURLOverrideKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           let url = validBackendURL(from: override) {
            return url
        }
        #endif
        let rawValue = configurationValue(for: backendBaseURLInfoKey)
        return validBackendURL(from: rawValue)
    }

    /// Parses backend base URL from build settings or overrides; applies Release vs Debug rules (HTTP allowed in DEBUG).
    private static func validBackendURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !isPlaceholderConfigurationValue(trimmed),
              let url = URL(string: trimmed),
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
        backendBaseURL != nil || isTestingOverridesEnabled
    }

    static var stripePublishableKey: String {
        let rawValue = configurationValue(for: stripePublishableKeyInfoKey)
        guard !rawValue.isEmpty, !isPlaceholderConfigurationValue(rawValue) else {
            return ""
        }
        return rawValue
    }

    nonisolated static var appAPIKey: String {
        let rawValue = configurationValue(for: appAPIKeyInfoKey)
        guard !rawValue.isEmpty, !isPlaceholderConfigurationValue(rawValue) else {
            return ""
        }
        return rawValue
    }

    nonisolated static func applyAppClientAuth(to request: inout URLRequest) {
        guard !appAPIKey.isEmpty else { return }
        request.setValue(appAPIKey, forHTTPHeaderField: "X-TenBelow-App-Key")
    }

    static var isStripeConfigured: Bool {
        stripePublishableKey.hasPrefix("pk_") || isTestingOverridesEnabled
    }

    static var hasLiveCheckoutConfiguration: Bool {
        backendBaseURL != nil && stripePublishableKey.hasPrefix("pk_")
    }

    /// UserDefaults key for DEBUG “Testing mode” in Settings (relaxed checkout / API when backend or Stripe is unset).
    static let testingModeUserDefaultsKey = "tb.testingModeEnabled"

    /// DEBUG-only: override plist `TENBELOW_BACKEND_BASE_URL` (e.g. `http://192.168.1.12:3000`) so a physical device can reach the Mac running `tenbelow-backend`.
    static let debugBackendBaseURLOverrideKey = "tb.debugBackendBaseURLOverride"

    #if DEBUG
    /// Applies `CommandLine.arguments` flags used by `TenBelowUITests` (call once at launch, before stores read config).
    static func applyLaunchArgumentsForTesting() {
        let args = Set(CommandLine.arguments)
        if args.contains("-UIEnableTestingMode") {
            UserDefaults.standard.set(true, forKey: testingModeUserDefaultsKey)
        }
        if args.contains("-UIDisableTestingMode") {
            UserDefaults.standard.set(false, forKey: testingModeUserDefaultsKey)
        }
    }
    #endif

    /// DEBUG-only override that keeps checkout/routes available while iterating UI/flows without a configured backend/Stripe.
    /// Defaults to `false` so missing production keys behave like Release; turn on under Settings → Developer in DEBUG builds.
    static var isTestingOverridesEnabled: Bool {
        #if DEBUG
        if let explicitValue = UserDefaults.standard.object(forKey: testingModeUserDefaultsKey) as? Bool {
            return explicitValue
        }
        return false
        #else
        return false
        #endif
    }

    static let stripeSetupMessage = "Checkout is turned off until Stripe is connected. Add your publishable key when you're ready to enable payments."

    static var checkoutSetupMessage: String {
        if isTestingOverridesEnabled && !hasLiveCheckoutConfiguration {
            return "Testing mode is on. Checkout uses simulated success until backend and Stripe are configured."
        }
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

    private nonisolated static func configurationValue(for key: String) -> String {
        String(Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func isPlaceholderConfigurationValue(_ value: String) -> Bool {
        let normalized = value.uppercased()
        return normalized.contains("YOUR_")
            || normalized.contains("PLACEHOLDER")
            || normalized.contains("REPLACE_ME")
    }

    // MARK: - Support (mailto)

    /// General support message (no order context).
    static var supportMailtoURL: URL? {
        guard var components = URLComponents(string: "mailto:\(supportEmail)") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "subject", value: "TenBelow support"),
        ]
        return components.url
    }

    /// Pre-filled exchange request. No backend is required; your team handles the thread in your inbox.
    static func exchangeRequestMailtoURL(orderId: String, buyerEmail: String?) -> URL? {
        let subject = "TenBelow exchange request — \(orderId)"
        var body = "Order ID: \(orderId)\n\n"
        if let email = buyerEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            body += "Email on order: \(email)\n\n"
        }
        body += "Item(s) to exchange:\n\nDesired replacement:\n\nReason for exchange:\n"
        guard var components = URLComponents(string: "mailto:\(supportEmail)") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}

enum TopLevelChromeMetrics {
    /// Used when a top-level screen hides the system nav bar and needs to place the
    /// floating cart button so it visually matches toolbar-based screens like Home/Drop.
    static let manualCartTrailingInset: CGFloat = 14
    static let manualCartTopInset: CGFloat = 6
}

enum TopLevelHeaderMetrics {
    /// Common horizontal inset for top-level screen content blocks.
    static let sharedHorizontalInset: CGFloat = 16
    /// Reused on title art that has transparent space at the bottom of the image asset.
    static let titleArtBottomTuck: CGFloat = -18
    static let homeTopInset: CGFloat = 2
    static let shopOuterHorizontalInset: CGFloat = 4
    static let shopTopInset: CGFloat = -8
    static let shopBottomInset: CGFloat = 0
    static let shopFilterTopInset: CGFloat = -2
    static let shopFilterBottomInset: CGFloat = 4
    static let dropTopInset: CGFloat = 0
    static let dropBottomInset: CGFloat = 16
    static let dropSellerHeaderBottomInset: CGFloat = 8
}

