import Foundation

/// Read-only diagnostics for Stripe/backend checkout readiness (Settings → Developer).
enum StripeSetupStatus {
    struct ChecklistItem: Identifiable {
        let id: String
        let title: String
        let isComplete: Bool
        let detail: String
    }

    static var items: [ChecklistItem] {
        [
            ChecklistItem(
                id: "backend",
                title: "Backend URL",
                isComplete: AppConstants.backendBaseURL != nil,
                detail: backendDetail
            ),
            ChecklistItem(
                id: "stripe_pk",
                title: "Stripe publishable key",
                isComplete: AppConstants.isStripeConfigured,
                detail: publishableKeyDetail
            ),
            ChecklistItem(
                id: "live_checkout",
                title: "Live checkout (Release builds)",
                isComplete: AppConstants.hasLiveCheckoutConfiguration,
                detail: liveCheckoutDetail
            ),
            ChecklistItem(
                id: "app_key",
                title: "App API key",
                isComplete: !AppConstants.appAPIKey.isEmpty,
                detail: AppConstants.appAPIKey.isEmpty ? "Set TENBELOW_APP_API_KEY to match backend APP_API_KEY." : "Configured."
            ),
            ChecklistItem(
                id: "buyer_account",
                title: "Signed-in buyer (for real checkout)",
                isComplete: MarketplaceAuthSession.hasAuthenticatedSession,
                detail: buyerAccountDetail
            ),
            ChecklistItem(
                id: "testing_mode",
                title: "Testing mode (Debug only)",
                isComplete: AppConstants.isTestingOverridesEnabled,
                detail: testingModeDetail
            ),
        ]
    }

    static var canSimulateCheckout: Bool {
        AppConstants.isTestingOverridesEnabled && !AppConstants.hasLiveCheckoutConfiguration
    }

    static var summaryLine: String {
        if AppConstants.hasLiveCheckoutConfiguration {
            return "Live checkout is configured."
        }
        if canSimulateCheckout {
            return "Testing mode: checkout will simulate success without Stripe."
        }
        #if DEBUG
        return "Turn on Testing mode below, or add Stripe test keys before end-of-week setup."
        #else
        return "Add pk_live_ and production backend URL for TestFlight checkout."
        #endif
    }

    private static var backendDetail: String {
        if let url = AppConstants.backendBaseURL {
            return url.absoluteString
        }
        return "Missing TENBELOW_BACKEND_BASE_URL."
    }

    private static var publishableKeyDetail: String {
        let key = AppConstants.stripePublishableKey
        guard !key.isEmpty else { return "Not set." }
        let prefix = String(key.prefix(12))
        return "\(prefix)… (\(keyModeLabel))"
    }

    private static var keyModeLabel: String {
        let key = AppConstants.stripePublishableKey
        if key.hasPrefix("pk_live_") { return "live" }
        if key.hasPrefix("pk_test_") { return "test" }
        return "unknown prefix"
    }

    private static var liveCheckoutDetail: String {
        #if DEBUG
        if AppConstants.hasLiveCheckoutConfiguration {
            return "Backend + publishable key ready for PaymentSheet."
        }
        return "Needs backend URL and pk_test (Debug) or pk_live (Release)."
        #else
        return AppConstants.hasLiveCheckoutConfiguration
            ? "Ready for PaymentSheet."
            : "Release requires pk_live_ and HTTPS backend."
        #endif
    }

    private static var buyerAccountDetail: String {
        if MarketplaceAuthSession.hasAuthenticatedSession {
            return "Buyer JWT present — checkout email must match saved buyer email."
        }
        return "Create a buyer account (not guest) before live checkout."
    }

    private static var testingModeDetail: String {
        #if DEBUG
        return AppConstants.isTestingOverridesEnabled
            ? "On — Pay button simulates order TB-TEST-…"
            : "Off — enable to test cart/checkout without Stripe."
        #else
        return "Not available in Release builds."
        #endif
    }
}
