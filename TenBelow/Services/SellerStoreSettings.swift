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

private struct SellerStoreSettingsUpdateRequest: Encodable {
    let shipping: SellerStoreSettingsShipping?
    let policies: SellerStoreSettingsPolicies?
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

extension SellerAPI {
    static func fetchStoreSettings(sellerId: String) async throws -> SellerStoreSettingsResponse {
        let url = CheckoutAPI.baseURL.appendingPathComponent("seller-store-settings/\(sellerId)")
        let (data, _) = try await performSellerAuthorizedRequest { URLRequest(url: url) }
        return try JSONDecoder().decode(SellerStoreSettingsResponse.self, from: data)
    }

    static func updateStoreSettings(
        sellerId: String,
        shipping: SellerStoreSettingsShipping? = nil,
        policies: SellerStoreSettingsPolicies? = nil
    ) async throws -> SellerStoreSettingsResponse {
        let url = CheckoutAPI.baseURL.appendingPathComponent("seller-store-settings/\(sellerId)")
        let (data, _) = try await performSellerAuthorizedRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                SellerStoreSettingsUpdateRequest(shipping: shipping, policies: policies)
            )
            return request
        }
        return try JSONDecoder().decode(SellerStoreSettingsResponse.self, from: data)
    }
}
