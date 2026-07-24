import Foundation

struct SellerStoreSettingsShipping: Codable, Equatable {
    var processingTime: String
    var minShipDays: Int
    var maxShipDays: Int
    var primaryRegion: String
    var offersInternational: Bool
    var internationalRegions: String
    var flatRateText: String
    var freeShippingThresholdText: String
    var shippingNote: String
}

struct SellerStoreSettingsPolicies: Codable, Equatable {
    var acceptsReturns: Bool
    var returnWindowDays: Int
    var allowsExchanges: Bool
    var allowsCancellations: Bool
    var cancellationWindowHours: Int
    var policyNote: String
}

struct SellerStoreSettingsResponse: Codable {
    let sellerId: String
    let shipping: SellerStoreSettingsShipping
    let policies: SellerStoreSettingsPolicies
    let updatedAt: String?
}

enum SellerStoreSettingsSync {
    private static let shippingKey = "sellerShippingSettingsData"
    private static let policiesKey = "sellerPolicySettingsData"

    static func refreshLocalCache(sellerId: String) async {
        let trimmedSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSellerId.isEmpty else { return }

        do {
            try await MarketplaceAuthSession.ensureSellerSessionReady()
            let settings = try await SellerAPI.fetchStoreSettings(sellerId: trimmedSellerId)
            applyToLocalCache(settings)
        } catch {
            // Keep local defaults when offline or session is unavailable.
        }
    }

    static func applyToLocalCache(_ settings: SellerStoreSettingsResponse) {
        if let data = try? JSONEncoder().encode(settings.shipping) {
            UserDefaults.standard.set(data, forKey: shippingKey)
        }
        if let data = try? JSONEncoder().encode(settings.policies) {
            UserDefaults.standard.set(data, forKey: policiesKey)
        }
    }

    static func loadLocalShipping() -> SellerStoreSettingsShipping? {
        guard let data = UserDefaults.standard.data(forKey: shippingKey) else { return nil }
        return try? JSONDecoder().decode(SellerStoreSettingsShipping.self, from: data)
    }

    static func loadLocalPolicies() -> SellerStoreSettingsPolicies? {
        guard let data = UserDefaults.standard.data(forKey: policiesKey) else { return nil }
        return try? JSONDecoder().decode(SellerStoreSettingsPolicies.self, from: data)
    }
}
