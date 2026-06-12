import Foundation
#if canImport(Security)
import Security
#endif

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
    private nonisolated static let hasMigratedTokenStorageKey = "auth.didMigrateTokensToKeychain"

    nonisolated static func applyAuthenticatedUserAuth(to request: inout URLRequest) {
        migrateTokensToKeychainIfNeeded()
        guard let token = currentBearerToken() else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    /// Seller-only writes (profile, products, media). Never falls back to a buyer token.
    nonisolated static func applySellerAuth(to request: inout URLRequest) {
        migrateTokensToKeychainIfNeeded()
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

    nonisolated static var hasActiveBuyerSession: Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "buyerAccountCreated") else { return false }
        let email = defaults.string(forKey: "buyerEmail")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !email.isEmpty else { return false }
        let token = KeychainTokenStore.string(for: buyerTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !token.isEmpty
    }

    nonisolated static var hasAuthenticatedSession: Bool {
        currentBearerToken() != nil
    }

    nonisolated private static func sellerBearerToken() -> String? {
        migrateTokensToKeychainIfNeeded()
        let token = KeychainTokenStore.string(for: sellerTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
    }

    static func clearBuyerSession() {
        migrateTokensToKeychainIfNeeded()
        KeychainTokenStore.delete(key: buyerTokenKey)
        UserDefaults.standard.removeObject(forKey: buyerTokenKey)
    }

    static func clearSellerSession() {
        migrateTokensToKeychainIfNeeded()
        KeychainTokenStore.delete(key: sellerTokenKey)
        UserDefaults.standard.removeObject(forKey: sellerTokenKey)
    }

    /// Stores a freshly issued buyer token after in-app account updates (email/password change).
    static func storeBuyerSessionToken(_ token: String) {
        migrateTokensToKeychainIfNeeded()
        KeychainTokenStore.set(token, for: buyerTokenKey)
        UserDefaults.standard.removeObject(forKey: buyerTokenKey)
    }

    /// Stores a freshly issued seller token after explicit seller sign-in.
    static func storeSellerSessionToken(_ token: String) {
        migrateTokensToKeychainIfNeeded()
        KeychainTokenStore.set(token, for: sellerTokenKey)
        UserDefaults.standard.removeObject(forKey: sellerTokenKey)
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

    /// Ensures a buyer JWT exists for checkout. Signed-in buyers refresh their session; guests receive a checkout-only session.
    static func ensureCheckoutSession(email: String, fullName: String) async throws {
        guard AppConstants.isBackendConfigured else {
            throw CheckoutAPIError(code: "configuration_error", message: AppConstants.checkoutSetupMessage)
        }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, trimmedName.count >= 2 else {
            throw CheckoutAPIError(code: "invalid_checkout_identity", message: "Enter your name and a valid email to continue.")
        }

        let defaults = UserDefaults.standard
        let buyerAccountCreated = defaults.bool(forKey: "buyerAccountCreated")
        let storedEmail = defaults.string(forKey: "buyerEmail")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if buyerAccountCreated, !storedEmail.isEmpty {
            guard storedEmail == normalizedEmail else {
                throw CheckoutAPIError(
                    code: "buyer_email_mismatch",
                    message: "Checkout email must match your signed-in buyer account."
                )
            }
            await syncAfterIdentityChange()
            guard hasActiveBuyerSession else {
                throw CheckoutAPIError(
                    code: "buyer_session_unavailable",
                    message: "Sign in to your buyer account before checking out."
                )
            }
            return
        }

        let response = try await BuyerAccountAPI.issueGuestCheckoutSession(
            email: normalizedEmail,
            fullName: trimmedName
        )
        storeBuyerSessionToken(response.token)
        defaults.set(normalizedEmail, forKey: "buyerEmail")
        defaults.set(trimmedName, forKey: "buyerFullName")
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

        if buyerAccountCreated, !buyerEmail.isEmpty {
            if !buyerFullName.isEmpty {
                await ensureBuyerAccount(fullName: buyerFullName, email: buyerEmail)
            }
            await refreshBuyerToken(email: buyerEmail)
        } else if role == "buyer",
                  !buyerEmail.isEmpty,
                  !(KeychainTokenStore.string(for: buyerTokenKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Preserve guest checkout JWTs until the buyer creates a full account.
        } else {
            clearBuyerSession()
        }

        if role == "seller", sellerAccountCreated, !sellerId.isEmpty {
            await refreshSellerToken(sellerId: sellerId, email: sellerEmail.isEmpty ? nil : sellerEmail)
        } else {
            clearSellerSession()
        }
    }

    private nonisolated static func currentBearerToken() -> String? {
        migrateTokensToKeychainIfNeeded()
        let defaults = UserDefaults.standard
        let role = defaults.string(forKey: "userRole") ?? ""

        if role == "seller",
           let token = KeychainTokenStore.string(for: sellerTokenKey),
           !token.isEmpty {
            return token
        }

        if let token = KeychainTokenStore.string(for: buyerTokenKey),
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
            storeBuyerSessionToken(response.token)
        } catch {
            clearBuyerSession()
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
        guard sellerBearerToken() != nil else {
            clearSellerSession()
            return
        }

        do {
            let response: MarketplaceAuthSessionResponse = try await issueSession(
                path: "auth/seller-session",
                body: SellerSessionRequest(sellerId: sellerId, email: email),
                includeSellerAuth: true
            )
            storeSellerSessionToken(response.token)
        } catch {
            clearSellerSession()
        }
    }

    private static func issueSession<T: Encodable, U: Decodable>(
        path: String,
        body: T,
        includeSellerAuth: Bool = false
    ) async throws -> U {
        let url = CheckoutAPI.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        if includeSellerAuth {
            applySellerAuth(to: &request)
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.tenBelow.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.userAuthenticationRequired)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(U.self, from: data)
    }

    nonisolated private static func migrateTokensToKeychainIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: hasMigratedTokenStorageKey) == false else { return }

        if let buyerToken = defaults.string(forKey: buyerTokenKey), !buyerToken.isEmpty {
            KeychainTokenStore.set(buyerToken, for: buyerTokenKey)
            defaults.removeObject(forKey: buyerTokenKey)
        }

        if let sellerToken = defaults.string(forKey: sellerTokenKey), !sellerToken.isEmpty {
            KeychainTokenStore.set(sellerToken, for: sellerTokenKey)
            defaults.removeObject(forKey: sellerTokenKey)
        }

        defaults.set(true, forKey: hasMigratedTokenStorageKey)
    }
}

private struct EmptyResponse: Decodable {
    let ok: Bool?
    let email: String?
}

private enum KeychainTokenStore {
    private nonisolated static let service = "com.tenbelow.auth"

    nonisolated static func string(for key: String) -> String? {
        #if canImport(Security)
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
        #else
        return UserDefaults.standard.string(forKey: key)
        #endif
    }

    nonisolated static func set(_ value: String, for key: String) {
        #if canImport(Security)
        guard let data = value.data(using: .utf8) else { return }
        var query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query.merge(attributes) { _, new in new }
            SecItemAdd(query as CFDictionary, nil)
        }
        #else
        UserDefaults.standard.set(value, forKey: key)
        #endif
    }

    nonisolated static func delete(key: String) {
        #if canImport(Security)
        SecItemDelete(baseQuery(for: key) as CFDictionary)
        #else
        UserDefaults.standard.removeObject(forKey: key)
        #endif
    }

    #if canImport(Security)
    private nonisolated static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
    #endif
}
