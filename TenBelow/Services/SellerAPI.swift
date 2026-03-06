import Foundation

enum SellerAPI {

    private static var baseURL: URL { CheckoutAPI.baseURL }

    static func createAccount(sellerId: String, email: String, businessName: String?) async throws -> CreateSellerResponse {
        let url = baseURL.appendingPathComponent("create-seller-account")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            CreateSellerRequest(sellerId: sellerId, email: email, businessName: businessName)
        )

        let (data, resp) = try await URLSession.shared.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "SellerAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(CreateSellerResponse.self, from: data)
    }

    static func onboardingStatus(sellerId: String) async throws -> SellerStatusResponse {
        let url = baseURL.appendingPathComponent("seller-onboarding-status/\(sellerId)")
        let (data, resp) = try await URLSession.shared.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "SellerAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(SellerStatusResponse.self, from: data)
    }

    static func onboardingLink(sellerId: String) async throws -> OnboardingLinkResponse {
        let url = baseURL.appendingPathComponent("seller-onboarding-link/\(sellerId)")
        let (data, resp) = try await URLSession.shared.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "SellerAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(OnboardingLinkResponse.self, from: data)
    }

    static func dashboardLink(sellerId: String) async throws -> DashboardLinkResponse {
        let url = baseURL.appendingPathComponent("seller-dashboard-link/\(sellerId)")
        let (data, resp) = try await URLSession.shared.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "SellerAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(DashboardLinkResponse.self, from: data)
    }
}
