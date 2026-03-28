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

        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "SellerAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(CreateSellerResponse.self, from: data)
    }

    static func onboardingStatus(sellerId: String) async throws -> SellerStatusResponse {
        let url = baseURL.appendingPathComponent("seller-onboarding-status/\(sellerId)")
        let (data, resp) = try await URLSession.tenBelow.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "SellerAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(SellerStatusResponse.self, from: data)
    }

    static func onboardingLink(sellerId: String) async throws -> OnboardingLinkResponse {
        let url = baseURL.appendingPathComponent("seller-onboarding-link/\(sellerId)")
        let (data, resp) = try await URLSession.tenBelow.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "SellerAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(OnboardingLinkResponse.self, from: data)
    }

    static func dashboardLink(sellerId: String) async throws -> DashboardLinkResponse {
        let url = baseURL.appendingPathComponent("seller-dashboard-link/\(sellerId)")
        let (data, resp) = try await URLSession.tenBelow.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "SellerAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(DashboardLinkResponse.self, from: data)
    }

    static func membershipStatus(sellerId: String) async throws -> SellerMembershipStatusResponse {
        let url = baseURL.appendingPathComponent("seller-membership-status/\(sellerId)")
        let (data, resp) = try await URLSession.tenBelow.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "SellerAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(SellerMembershipStatusResponse.self, from: data)
    }

    static func syncMembership(_ payload: SellerMembershipSyncRequest) async throws -> SellerMembershipStatusResponse {
        let url = baseURL.appendingPathComponent("seller-membership-sync")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "SellerAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(SellerMembershipStatusResponse.self, from: data)
    }

    static func fetchProfiles() async throws -> [SellerProfile] {
        let url = baseURL.appendingPathComponent("seller-profiles")
        return try await URLSession.tenBelow.decode(SellerProfilesResponse.self, from: url).sellers
    }

    static func fetchProfile(sellerId: String) async throws -> SellerProfile {
        let url = baseURL.appendingPathComponent("seller-profiles/\(sellerId)")
        return try await URLSession.tenBelow.decode(SellerProfileResponse.self, from: url).seller
    }

    static func updateProfile(
        sellerId: String,
        profile: UpdateSellerProfileRequest
    ) async throws -> SellerProfile {
        let url = baseURL.appendingPathComponent("seller-profiles/\(sellerId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(profile)

        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "SellerAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SellerProfileResponse.self, from: data).seller
    }

    static func upsertProduct(
        sellerId: String,
        productId: String,
        product: UpsertSellerProductRequest
    ) async throws -> RemoteProduct {
        let url = baseURL.appendingPathComponent("seller-products/\(sellerId)/\(productId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(product)

        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "SellerAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SellerProductResponse.self, from: data).product
    }

    static func uploadMedia(
        sellerId: String,
        productId: String,
        mediaKind: String,
        slot: String,
        fileExtension: String,
        contentType: String,
        data: Data
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("seller-media/\(sellerId)/\(productId)/\(mediaKind)/\(slot)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(fileExtension, forHTTPHeaderField: "X-File-Extension")
        request.httpBody = data

        let (responseData, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: responseData, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "SellerAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        struct UploadResponse: Codable {
            let url: String
        }

        return try JSONDecoder().decode(UploadResponse.self, from: responseData).url
    }
}
