import Foundation

private struct SellerAPIServerError: Decodable {
    let error: String
}

private struct SellerLoginRequest: Encodable {
    let identifier: String
    let password: String
}

struct SellerLoginResponse: Decodable {
    let token: String
    let role: String
    let sellerId: String
    let sellerEmail: String?
    let businessName: String?
}

struct SellerAPIError: LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? { message }

    var isSellerAlreadyExists: Bool {
        statusCode == 409 && message.localizedCaseInsensitiveContains("seller already exists")
    }

    var isSellerSessionRequired: Bool {
        guard statusCode == 401 else { return false }
        let lower = message.lowercased()
        return lower.contains("seller session")
            || lower.contains("seller account")
            || lower.contains("sign in")
            || lower.contains("authenticated")
    }
}

enum SellerAPI {

    private static var baseURL: URL { CheckoutAPI.baseURL }

    static func isSellerAlreadyExistsError(_ error: Error) -> Bool {
        (error as? SellerAPIError)?.isSellerAlreadyExists == true
    }

    @discardableResult
    static func createAccount(sellerId: String, email: String, businessName: String?, password: String? = nil) async throws -> CreateSellerResponse {
        let url = baseURL.appendingPathComponent("create-seller-account")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(
            CreateSellerRequest(sellerId: sellerId, email: email, businessName: businessName, password: password)
        )

        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = serverErrorMessage(from: data)
            throw SellerAPIError(statusCode: http.statusCode, message: msg)
        }
        return try JSONDecoder().decode(CreateSellerResponse.self, from: data)
    }

    static func login(identifier: String, password: String) async throws -> SellerLoginResponse {
        let url = baseURL.appendingPathComponent("auth/seller-login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(SellerLoginRequest(identifier: identifier, password: password))

        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SellerAPIError(statusCode: http.statusCode, message: serverErrorMessage(from: data))
        }
        return try JSONDecoder().decode(SellerLoginResponse.self, from: data)
    }

    private static func serverErrorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(SellerAPIServerError.self, from: data) {
            return decoded.error
        }
        return String(data: data, encoding: .utf8) ?? "Server error"
    }

    private static func mapSessionError(_ error: Error) -> Error {
        if let sessionError = error as? MarketplaceAuthSessionError {
            return SellerAPIError(statusCode: 401, message: sessionError.localizedDescription)
        }
        return error
    }

    /// Ensures a seller JWT is present, performs the request, and retries once after refresh on seller-session 401s.
    private static func performSellerAuthorizedRequest(
        _ build: () throws -> URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            try await MarketplaceAuthSession.ensureSellerSessionReady()
        } catch {
            throw mapSessionError(error)
        }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            var authorized = request
            authorized.cachePolicy = .reloadIgnoringLocalCacheData
            authorized.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            authorized.setValue("no-cache", forHTTPHeaderField: "Pragma")
            AppConstants.applyAppClientAuth(to: &authorized)
            MarketplaceAuthSession.applySellerAuth(to: &authorized)
            let (data, response) = try await URLSession.tenBelow.data(for: authorized)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, http)
        }

        func failure(from data: Data, statusCode: Int) -> SellerAPIError {
            SellerAPIError(statusCode: statusCode, message: serverErrorMessage(from: data))
        }

        let (data, http) = try await send(build())
        if (200...299).contains(http.statusCode) {
            return (data, http)
        }

        var apiError = failure(from: data, statusCode: http.statusCode)
        if apiError.isSellerSessionRequired {
            await MarketplaceAuthSession.syncAfterIdentityChange()
            if MarketplaceAuthSession.hasActiveSellerSession {
                let (retryData, retryHTTP) = try await send(build())
                if (200...299).contains(retryHTTP.statusCode) {
                    return (retryData, retryHTTP)
                }
                apiError = failure(from: retryData, statusCode: retryHTTP.statusCode)
            }
        }

        throw apiError
    }

    static func onboardingStatus(sellerId: String) async throws -> SellerStatusResponse {
        let url = baseURL.appendingPathComponent("seller-onboarding-status/\(sellerId)")
        let request = URLRequest(url: url)
        let (data, _) = try await performSellerAuthorizedRequest { request }
        return try JSONDecoder().decode(SellerStatusResponse.self, from: data)
    }

    static func onboardingLink(sellerId: String) async throws -> OnboardingLinkResponse {
        let url = baseURL.appendingPathComponent("seller-onboarding-link/\(sellerId)")
        let (data, _) = try await performSellerAuthorizedRequest { URLRequest(url: url) }
        return try JSONDecoder().decode(OnboardingLinkResponse.self, from: data)
    }

    static func dashboardLink(sellerId: String) async throws -> DashboardLinkResponse {
        let url = baseURL.appendingPathComponent("seller-dashboard-link/\(sellerId)")
        let (data, _) = try await performSellerAuthorizedRequest { URLRequest(url: url) }
        return try JSONDecoder().decode(DashboardLinkResponse.self, from: data)
    }

    static func membershipStatus(sellerId: String) async throws -> SellerMembershipStatusResponse {
        let url = baseURL.appendingPathComponent("seller-membership-status/\(sellerId)")
        let (data, _) = try await performSellerAuthorizedRequest { URLRequest(url: url) }
        return try JSONDecoder().decode(SellerMembershipStatusResponse.self, from: data)
    }

    /// Opens in Safari; membership activates after Stripe Checkout + webhooks.
    static func createSellerMembershipCheckoutSession(sellerId: String) async throws -> URL {
        let url = baseURL.appendingPathComponent("create-seller-membership-checkout")
        let (data, _) = try await performSellerAuthorizedRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            struct Body: Encodable { let sellerId: String }
            request.httpBody = try JSONEncoder().encode(Body(sellerId: sellerId))
            return request
        }
        let decoded = try JSONDecoder().decode(CreateSellerMembershipCheckoutResponse.self, from: data)
        guard let checkout = URL(string: decoded.url) else {
            throw SellerAPIError(statusCode: -1, message: "Invalid checkout URL")
        }
        return checkout
    }

    static func syncMembership(_ payload: SellerMembershipSyncRequest) async throws -> SellerMembershipStatusResponse {
        let url = baseURL.appendingPathComponent("seller-membership-sync")
        let (data, _) = try await performSellerAuthorizedRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            return request
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
        let (data, _) = try await performSellerAuthorizedRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(profile)
            return request
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SellerProfileResponse.self, from: data).seller
    }

    static func fetchSellerProducts(sellerId: String) async throws -> [RemoteProduct] {
        let url = baseURL.appendingPathComponent("seller-products/\(sellerId)")
        let (data, _) = try await performSellerAuthorizedRequest { URLRequest(url: url) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SellerProductsListResponse.self, from: data).products
    }

    static func upsertProduct(
        sellerId: String,
        productId: String,
        product: UpsertSellerProductRequest
    ) async throws -> RemoteProduct {
        let url = baseURL.appendingPathComponent("seller-products/\(sellerId)/\(productId)")
        let (data, _) = try await performSellerAuthorizedRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(product)
            return request
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SellerProductResponse.self, from: data).product
    }

    static func removeProduct(
        sellerId: String,
        productId: String,
        reason: String
    ) async throws {
        let url = baseURL.appendingPathComponent("seller-products/\(sellerId)/\(productId)/remove")
        _ = try await performSellerAuthorizedRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(RemoveSellerProductRequest(reason: reason))
            return request
        }
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
        let (responseData, _) = try await performSellerAuthorizedRequest {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.setValue(fileExtension, forHTTPHeaderField: "X-File-Extension")
            request.httpBody = data
            return request
        }

        struct UploadResponse: Codable {
            let url: String
        }

        return try JSONDecoder().decode(UploadResponse.self, from: responseData).url
    }
}
