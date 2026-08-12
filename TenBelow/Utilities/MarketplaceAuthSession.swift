import Foundation
import Combine
#if canImport(Security)
import Security
#endif

struct AccountModerationStatus: Codable, Equatable {
    var isFlagged: Bool = false
    var isFrozen: Bool = false
    var flagReason: String?
    var freezeReason: String?
    var flaggedAt: String?
    var frozenAt: String?
    var lastAction: String?
    var lastActionAt: String?
    var lastEmailStatus: String?
    var lastEmailSentAt: String?
    var lastEmailError: String?

    var hasModerationNotice: Bool {
        isFlagged || isFrozen
    }

    var headline: String {
        if isFrozen {
            return "Account frozen"
        }
        if isFlagged {
            return "Account flagged for review"
        }
        return ""
    }

    var detailMessage: String {
        if isFrozen {
            if let freezeReason, !freezeReason.isEmpty {
                return freezeReason
            }
            return "Your account is temporarily frozen. Check your email for details or contact support@tenbelow.com."
        }
        if isFlagged {
            if let flagReason, !flagReason.isEmpty {
                return flagReason
            }
            return "Your account was flagged for review. Check your email for details."
        }
        return ""
    }

    var supportFooter: String {
        "If you believe this was a mistake, contact support@tenbelow.com."
    }
}

struct AccountModerationSessionError: Error {
    let status: AccountModerationStatus
}

private struct AccountModerationStatusResponse: Decodable {
    let ok: Bool?
    let role: String?
    let accountModeration: AccountModerationStatus?
}

private struct AccountModerationBlockedResponse: Decodable {
    let error: String?
    let code: String?
    let accountModeration: AccountModerationStatus?
}

enum AccountModerationAPI {
    static func fetchCurrentStatus() async throws -> AccountModerationStatus {
        let url = CheckoutAPI.baseURL.appendingPathComponent("auth/account-moderation-status")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)

        let (data, response) = try await URLSession.tenBelow.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 403,
           let blocked = try? JSONDecoder().decode(AccountModerationBlockedResponse.self, from: data),
           let moderation = blocked.accountModeration {
            return moderation
        }

        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(AccountModerationStatusResponse.self, from: data)
        return payload.accountModeration ?? AccountModerationStatus()
    }
}

@MainActor
final class AccountModerationStore: ObservableObject {
    static let shared = AccountModerationStore()

    @Published private(set) var status = AccountModerationStatus()

    private init() {
        status = Self.loadCachedStatus()
    }

    var hasModerationNotice: Bool {
        status.hasModerationNotice
    }

    func apply(_ next: AccountModerationStatus?) {
        let resolved = next ?? AccountModerationStatus()
        status = resolved
        Self.cacheStatus(resolved)
    }

    func refresh() async {
        guard AppConstants.isBackendConfigured else {
            apply(nil)
            return
        }
        guard MarketplaceAuthSession.hasAuthenticatedSession else {
            apply(nil)
            return
        }

        do {
            let remote = try await AccountModerationAPI.fetchCurrentStatus()
            apply(remote)
        } catch {
            #if DEBUG
            print("Account moderation refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    func clear() {
        apply(nil)
    }

    private static func cacheKey() -> String {
        let defaults = UserDefaults.standard
        let role = defaults.string(forKey: "userRole") ?? "guest"
        if role == "seller" {
            let sellerId = defaults.string(forKey: "sellerSellerId") ?? ""
            return "accountModeration.cache.seller.\(sellerId)"
        }
        let email = defaults.string(forKey: "buyerEmail")?.lowercased() ?? ""
        return "accountModeration.cache.buyer.\(email)"
    }

    private static func loadCachedStatus() -> AccountModerationStatus {
        guard let data = UserDefaults.standard.data(forKey: cacheKey()),
              let decoded = try? JSONDecoder().decode(AccountModerationStatus.self, from: data) else {
            return AccountModerationStatus()
        }
        return decoded
    }

    private static func cacheStatus(_ status: AccountModerationStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey())
    }
}

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
    let accountModeration: AccountModerationStatus?
}

private struct MarketplaceAuthErrorResponse: Decodable {
    let error: String?
    let code: String?
    let accountModeration: AccountModerationStatus?
}

private struct MarketplaceSessionTokenClaims {
    let role: String?
    let sellerId: String?
    let exp: TimeInterval?
}

enum MarketplaceAuthSessionError: LocalizedError {
    case sellerSessionUnavailable

    var errorDescription: String? {
        switch self {
        case .sellerSessionUnavailable:
            return """
            Could not connect your seller account to the server. Check your internet connection, then open \
            Settings → Sign in as seller if this keeps happening.
            """
        }
    }
}

enum MarketplaceAuthSession {
    private nonisolated static let buyerTokenKey = "auth.buyerToken"
    private nonisolated static let sellerTokenKey = "auth.sellerToken"
    private nonisolated static let hasMigratedTokenStorageKey = "auth.didMigrateTokensToKeychain"
    private nonisolated static let tokenRefreshLeewaySeconds: TimeInterval = 120

    nonisolated static func applyAuthenticatedUserAuth(to request: inout URLRequest) {
        migrateTokensToKeychainIfNeeded()
        guard let token = currentBearerToken() else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    /// Seller-only writes (profile, products, media). Never falls back to a buyer token.
    nonisolated static func applySellerAuth(to request: inout URLRequest, token overrideToken: String? = nil) {
        migrateTokensToKeychainIfNeeded()
        let token = overrideToken?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? sellerBearerToken()
        guard let token, !token.isEmpty else { return }
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

    /// Prefer the seller ID embedded in the JWT so drop/profile APIs stay aligned with the server account.
    nonisolated static func authenticatedSellerId() -> String? {
        if let token = sellerBearerToken(),
           let claim = sellerIdClaim(from: token) {
            return claim
        }
        let stored = UserDefaults.standard.string(forKey: "sellerSellerId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? nil : stored
    }

    nonisolated static var hasActiveBuyerSession: Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "buyerAccountCreated") else { return false }
        let email = defaults.string(forKey: "buyerEmail")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !email.isEmpty else { return false }
        let token = KeychainTokenStore.string(for: buyerTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !token.isEmpty && !isTokenExpired(token)
    }

    nonisolated static var hasAuthenticatedSession: Bool {
        currentBearerToken() != nil
    }

    nonisolated private static func sellerBearerToken() -> String? {
        migrateTokensToKeychainIfNeeded()
        let token = KeychainTokenStore.string(for: sellerTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty, !isTokenExpired(token, leeway: 0) else { return nil }
        return token
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

    /// Call before any seller write (profile, products, media). Refreshes or bootstraps the seller JWT when possible.
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

        await AccountModerationStore.shared.refresh()
    }

    private nonisolated static func currentBearerToken() -> String? {
        migrateTokensToKeychainIfNeeded()
        let defaults = UserDefaults.standard
        let role = defaults.string(forKey: "userRole") ?? ""

        if role == "seller", let token = sellerBearerToken() {
            return token
        }

        if let token = KeychainTokenStore.string(for: buyerTokenKey),
           !token.isEmpty,
           !isTokenExpired(token) {
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
            await MainActor.run {
                AccountModerationStore.shared.apply(response.accountModeration)
            }
        } catch let moderation as AccountModerationSessionError {
            await MainActor.run {
                AccountModerationStore.shared.apply(moderation.status)
            }
            clearBuyerSession()
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
        let storedRawToken = KeychainTokenStore.string(for: sellerTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tokenSellerId = sellerIdClaim(from: storedRawToken) ?? sellerId

        if !storedRawToken.isEmpty, !isTokenExpired(storedRawToken, leeway: 0) {
            if !shouldRefreshSellerToken(storedRawToken) {
                reconcileLocalSellerIdentity(canonicalSellerId: tokenSellerId)
                return
            }

            do {
                let response: MarketplaceAuthSessionResponse = try await issueSession(
                    path: "auth/seller-session",
                    body: SellerSessionRequest(sellerId: tokenSellerId, email: email),
                    sellerAuthToken: storedRawToken
                )
                storeSellerSessionToken(response.token)
                reconcileLocalSellerIdentity(
                    canonicalSellerId: response.sellerId ?? tokenSellerId
                )
                await MainActor.run {
                    AccountModerationStore.shared.apply(response.accountModeration)
                }
                return
            } catch let moderation as AccountModerationSessionError {
                await MainActor.run {
                    AccountModerationStore.shared.apply(moderation.status)
                }
                clearSellerSession()
                return
            } catch {
                // Fall through to bootstrap when refresh fails (expired token, network blip, etc.).
            }
        }

        do {
            let response: MarketplaceAuthSessionResponse = try await issueSession(
                path: "auth/seller-session-bootstrap",
                body: SellerSessionRequest(sellerId: tokenSellerId, email: email)
            )
            storeSellerSessionToken(response.token)
            reconcileLocalSellerIdentity(
                canonicalSellerId: response.sellerId ?? tokenSellerId
            )
            await MainActor.run {
                AccountModerationStore.shared.apply(response.accountModeration)
            }
        } catch let moderation as AccountModerationSessionError {
            await MainActor.run {
                AccountModerationStore.shared.apply(moderation.status)
            }
            clearSellerSession()
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost || urlError.code == .timedOut {
            // Stay signed in locally when offline; seller tools can retry when connectivity returns.
        } catch {
            clearSellerSession()
        }
    }

    private nonisolated static func isTokenExpired(_ token: String, leeway: TimeInterval = 0) -> Bool {
        guard let exp = tokenClaims(from: token)?.exp else { return false }
        return Date(timeIntervalSince1970: exp).timeIntervalSinceNow <= leeway
    }

    private nonisolated static func shouldRefreshSellerToken(_ token: String) -> Bool {
        isTokenExpired(token, leeway: tokenRefreshLeewaySeconds)
    }

    private nonisolated static func tokenClaims(from token: String) -> MarketplaceSessionTokenClaims? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingCount = (4 - payload.count % 4) % 4
        payload.append(String(repeating: "=", count: paddingCount))

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let role = json["role"] as? String
        let sellerId = json["sellerId"] as? String
        let exp: TimeInterval? = {
            if let number = json["exp"] as? NSNumber {
                return number.doubleValue
            }
            if let intValue = json["exp"] as? Int {
                return TimeInterval(intValue)
            }
            return nil
        }()

        return MarketplaceSessionTokenClaims(role: role, sellerId: sellerId, exp: exp)
    }

    private nonisolated static func sellerIdClaim(from token: String) -> String? {
        guard let claims = tokenClaims(from: token),
              claims.role == "seller"
        else {
            return nil
        }

        let sellerId = claims.sellerId?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return sellerId.isEmpty ? nil : sellerId
    }

    private static func reconcileLocalSellerIdentity(canonicalSellerId: String) {
        let canonical = canonicalSellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty else { return }

        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: "sellerSellerId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard stored != canonical else { return }

        defaults.set(canonical, forKey: "sellerSellerId")

        if let profile = SellerProfile.locallyStoredProfile(), profile.id != canonical {
            profile.replacingAccountID(with: canonical).storeLocally()
        }
    }

    private static func issueSession<T: Encodable, U: Decodable>(
        path: String,
        body: T,
        sellerAuthToken: String? = nil
    ) async throws -> U {
        let url = CheckoutAPI.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        if let sellerAuthToken {
            applySellerAuth(to: &request, token: sellerAuthToken)
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.tenBelow.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 403,
           let blocked = try? JSONDecoder().decode(MarketplaceAuthErrorResponse.self, from: data),
           let moderation = blocked.accountModeration,
           moderation.isFrozen {
            throw AccountModerationSessionError(status: moderation)
        }

        guard (200...299).contains(http.statusCode) else {
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
