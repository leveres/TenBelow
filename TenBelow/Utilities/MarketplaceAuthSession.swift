import Foundation

private struct BuyerSessionRequest: Encodable {
    let email: String
}

private struct BuyerAccountRequest: Encodable {
    let email: String
    let fullName: String
}

private struct SellerSessionRequest: Encodable {
    let sellerId: String
    let email: String?
}

private struct MarketplaceAuthSessionResponse: Decodable {
    let token: String
    let role: String
    let buyerEmail: String?
    let sellerId: String?
}

enum MarketplaceAuthSessionError: LocalizedError {
    case sellerSessionUnavailable

    var errorDescription: String? {
        switch self {
        case .sellerSessionUnavailable:
            return """
            Could not sign in as your seller account on the server. Open Settings, confirm you are in Seller mode, \
            and use the same seller id and email you registered with while online.
            """
        }
    }
}

enum MarketplaceAuthSession {
    private nonisolated static let buyerTokenKey = "auth.buyerToken"
    private nonisolated static let sellerTokenKey = "auth.sellerToken"

    nonisolated static func applyAuthenticatedUserAuth(to request: inout URLRequest) {
        guard let token = currentBearerToken() else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    /// Seller-only writes (profile, products, media). Never falls back to a buyer token.
    nonisolated static func applySellerAuth(to request: inout URLRequest) {
        guard let token = sellerBearerToken() else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    nonisolated static var hasActiveSellerSession: Bool {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "userRole") == "seller",
              defaults.bool(forKey: "sellerAccountCreated") else {
            return false
        }
        return sellerBearerToken() != nil
    }

    nonisolated private static func sellerBearerToken() -> String? {
        let token = UserDefaults.standard.string(forKey: sellerTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
    }

    static func clearBuyerSession() {
        UserDefaults.standard.removeObject(forKey: buyerTokenKey)
    }

    static func clearSellerSession() {
        UserDefaults.standard.removeObject(forKey: sellerTokenKey)
    }

    /// Stores a freshly issued buyer token after in-app account updates (email/password change).
    static func storeBuyerSessionToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: buyerTokenKey)
    }

    /// Call before any seller write (profile, products, media). Refreshes the seller JWT when possible.
    static func ensureSellerSessionReady() async throws {
        guard AppConstants.isBackendConfigured else {
            throw MarketplaceAuthSessionError.sellerSessionUnavailable
        }

        let defaults = UserDefaults.standard
        let role = defaults.string(forKey: "userRole") ?? ""
        let sellerId = defaults.string(forKey: "sellerSellerId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sellerAccountCreated = defaults.bool(forKey: "sellerAccountCreated")

        guard role == "seller", sellerAccountCreated, !sellerId.isEmpty else {
            throw MarketplaceAuthSessionError.sellerSessionUnavailable
        }

        await syncAfterIdentityChange()

        guard hasActiveSellerSession else {
            throw MarketplaceAuthSessionError.sellerSessionUnavailable
        }
    }

    static func syncAfterIdentityChange() async {
        let defaults = UserDefaults.standard
        let role = defaults.string(forKey: "userRole") ?? ""
        let buyerFullName = defaults.string(forKey: "buyerFullName")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let buyerEmail = defaults.string(forKey: "buyerEmail")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let sellerId = defaults.string(forKey: "sellerSellerId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sellerEmail = defaults.string(forKey: "sellerEmail")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let buyerAccountCreated = defaults.bool(forKey: "buyerAccountCreated")
        let sellerAccountCreated = defaults.bool(forKey: "sellerAccountCreated")

        if buyerAccountCreated, !buyerEmail.isEmpty, !buyerFullName.isEmpty {
            await ensureBuyerAccount(fullName: buyerFullName, email: buyerEmail)
            await refreshBuyerToken(email: buyerEmail)
        } else {
            defaults.removeObject(forKey: buyerTokenKey)
        }

        if role == "seller", sellerAccountCreated, !sellerId.isEmpty {
            await refreshSellerToken(sellerId: sellerId, email: sellerEmail.isEmpty ? nil : sellerEmail)
        } else {
            defaults.removeObject(forKey: sellerTokenKey)
        }
    }

    private nonisolated static func currentBearerToken() -> String? {
        let defaults = UserDefaults.standard
        let role = defaults.string(forKey: "userRole") ?? ""

        if role == "seller",
           let token = defaults.string(forKey: sellerTokenKey),
           !token.isEmpty {
            return token
        }

        if let token = defaults.string(forKey: buyerTokenKey),
           !token.isEmpty {
            return token
        }

        return nil
    }

    private static func refreshBuyerToken(email: String) async {
        do {
            let response: MarketplaceAuthSessionResponse = try await issueSession(
                path: "auth/buyer-session",
                body: BuyerSessionRequest(email: email)
            )
            UserDefaults.standard.set(response.token, forKey: buyerTokenKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: buyerTokenKey)
        }
    }

    private static func ensureBuyerAccount(fullName: String, email: String) async {
        do {
            let _: EmptyResponse = try await issueSession(
                path: "auth/buyer-account",
                body: BuyerAccountRequest(email: email, fullName: fullName)
            )
        } catch { }
    }

    private static func refreshSellerToken(sellerId: String, email: String?) async {
        do {
            let response: MarketplaceAuthSessionResponse = try await issueSession(
                path: "auth/seller-session",
                body: SellerSessionRequest(sellerId: sellerId, email: email)
            )
            UserDefaults.standard.set(response.token, forKey: sellerTokenKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: sellerTokenKey)
        }
    }

    private static func issueSession<T: Encodable, U: Decodable>(path: String, body: T) async throws -> U {
        let url = CheckoutAPI.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.tenBelow.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.userAuthenticationRequired)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(U.self, from: data)
    }
}

private struct EmptyResponse: Decodable {
    let ok: Bool?
    let email: String?
}
