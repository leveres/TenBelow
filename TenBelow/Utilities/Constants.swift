import Foundation

enum AppConstants {
    /// Injected via target build settings → `Info.plist` (`$(TENBELOW_*)`). For App Store Release, set HTTPS production URL, `pk_live_…`, and an app API key that matches the backend.
    private nonisolated static let backendBaseURLInfoKey = "TENBELOW_BACKEND_BASE_URL"
    private nonisolated static let stripePublishableKeyInfoKey = "TENBELOW_STRIPE_PUBLISHABLE_KEY"
    private nonisolated static let appAPIKeyInfoKey = "TENBELOW_APP_API_KEY"

    // MARK: - Shipping

    static let freeShippingThresholdCents = MarketplaceShippingCalculator.freeShippingThresholdCents
    static let minimumOrderCents          = 1500

    // MARK: - Cache File Names

    static let catalogCacheFile = "products_cache.json"
    static let configCacheFile  = "config_cache.json"

    // MARK: - Bundle Fallback File Names

    static let catalogFallbackFile = "products_fallback"
    static let configFallbackFile  = "config_fallback"

    // MARK: - Marketplace / Reporting

    static let reportListingEmail = "admin@innovativecodeworks.com"

    /// Buyer support — exchange requests and general help (opens Mail via `mailto:`).
    static let supportEmail = "admin@innovativecodeworks.com"

    // MARK: - Seller Subscription

    static let sellerSubscriptionProductID = "com.innovativecodeworks.com.TenBelow.seller.monthly"
    static let sellerSubscriptionFallbackPrice = "$12.99"
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    // MARK: - Stripe (replace with your publishable key from dashboard.stripe.com)

    #if DEBUG
    nonisolated(unsafe) private static var debugBackendBaseURLOverrideSnapshot: String?

    /// Keeps DEBUG LAN overrides available to `backendBaseURL` from background media loaders without touching `UserDefaults` off the main actor.
    @MainActor
    static func refreshDebugBackendBaseURLOverrideCache() {
        let rawValue = configurationValue(for: backendBaseURLInfoKey)
        let stored = UserDefaults.standard.string(forKey: debugBackendBaseURLOverrideKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let stored, !stored.isEmpty, let url = validBackendURL(from: stored) else {
            debugBackendBaseURLOverrideSnapshot = nil
            return
        }

        if shouldIgnoreDebugBackendOverride(url, configuredBackendValue: rawValue) {
            UserDefaults.standard.removeObject(forKey: debugBackendBaseURLOverrideKey)
            debugBackendBaseURLOverrideSnapshot = nil
        } else {
            debugBackendBaseURLOverrideSnapshot = stored
        }
    }
    #endif

    nonisolated static var backendBaseURL: URL? {
        let rawValue = configurationValue(for: backendBaseURLInfoKey)
        #if DEBUG
        if let override = debugBackendBaseURLOverrideSnapshot,
           !override.isEmpty,
           let url = validBackendURL(from: override),
           !shouldIgnoreDebugBackendOverride(url, configuredBackendValue: rawValue) {
            return url
        }
        #endif
        return validBackendURL(from: rawValue)
    }

    /// Parses backend base URL from build settings or overrides; applies Release vs Debug rules (HTTP allowed in DEBUG).
    nonisolated private static func validBackendURL(from rawValue: String) -> URL? {
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

    #if DEBUG
    nonisolated private static func shouldIgnoreDebugBackendOverride(_ overrideURL: URL, configuredBackendValue: String) -> Bool {
        guard configuredBackendValue.contains("tenbelow.onrender.com") else { return false }
        return overrideURL.scheme?.lowercased() != "https"
    }
    #endif

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
        isAllowedStripePublishableKey(stripePublishableKey) || isTestingOverridesEnabled
    }

    static var hasLiveCheckoutConfiguration: Bool {
        backendBaseURL != nil && isAllowedStripePublishableKey(stripePublishableKey)
    }

    private nonisolated static func isAllowedStripePublishableKey(_ key: String) -> Bool {
        guard key.hasPrefix("pk_") else { return false }
        #if DEBUG
        return true
        #else
        return key.hasPrefix("pk_live_")
        #endif
    }

    /// UserDefaults key for DEBUG “Testing mode” in Settings (relaxed checkout / API when backend or Stripe is unset).
    static let testingModeUserDefaultsKey = "tb.testingModeEnabled"

    /// DEBUG-only: override plist `TENBELOW_BACKEND_BASE_URL` (e.g. `http://192.168.1.12:3000`) so a physical device can reach the Mac running `tenbelow-backend`.
    nonisolated static let debugBackendBaseURLOverrideKey = "tb.debugBackendBaseURLOverride"

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

    /// In-app account deletion initiation for App Store review while automated deletion is being built.
    static func accountDeletionMailtoURL(accountType: String, email: String?) -> URL? {
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var body = "Account type: \(accountType)\n"
        if !trimmedEmail.isEmpty {
            body += "Account email: \(trimmedEmail)\n"
        }
        body += "\nPlease delete my TenBelow account and associated personal data, except where TenBelow must retain records for legal, fraud-prevention, tax, payment, or order-support obligations.\n"

        guard var components = URLComponents(string: "mailto:\(supportEmail)") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "subject", value: "TenBelow account deletion request"),
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
    /// Extra scroll padding below the last home section (Maker spotlight).
    static let homeBottomInset: CGFloat = 24
    /// Additional clearance for the floating tab bar capsule (iOS 18+), on top of `homeBottomInset`.
    static let homeFloatingTabBarClearance: CGFloat = 28

    /// Bottom padding for home scroll content; includes safe area when the reader reports it.
    static func homeScrollBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        homeBottomInset + homeFloatingTabBarClearance + max(safeAreaBottom, 0)
    }
    static let shopOuterHorizontalInset: CGFloat = 4
    static let shopTopInset: CGFloat = -20
    static let shopBottomInset: CGFloat = 0
    static let shopTitleImageHeight: CGFloat = 126
    static let shopTitleScale: CGFloat = 1.08
    static let shopTitleBottomTuck: CGFloat = -22
    static let shopFilterRowSpacing: CGFloat = 3
    static let shopGridTopInset: CGFloat = 6
    static let shopGridSpacing: CGFloat = 12
    static let shopScrollBottomInset: CGFloat = 16

    static func shopScrollBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        shopScrollBottomInset + homeFloatingTabBarClearance + max(safeAreaBottom, 0)
    }
    static let dropTopInset: CGFloat = 0
    static let dropBottomInset: CGFloat = 16
    static let dropSellerHeaderBottomInset: CGFloat = 8
}

