//
//  PushDeviceRegistration.swift
//

import Foundation

enum PushDeviceRegistration {
    private static let lastUploadedKey = "pushRegistration.lastUploadedToken"

    /// Call after APNs gives a token, and when account context changes (role / seller id / buyer email).
    static func uploadTokenIfNeeded(_ deviceTokenHex: String) async {
        #if os(iOS)
        guard !deviceTokenHex.isEmpty else { return }
        guard AppConstants.isBackendConfigured else { return }

        let userKey = currentUserKeyForPush()
        let payload = RegisterPushDeviceRequest(
            deviceToken: deviceTokenHex,
            userKey: userKey,
            platform: "ios",
            bundleId: Bundle.main.bundleIdentifier ?? ""
        )

        if UserDefaults.standard.string(forKey: lastUploadedKey) == "\(userKey)|\(deviceTokenHex)" {
            return
        }

        do {
            try await postRegistration(payload)
            UserDefaults.standard.set("\(userKey)|\(deviceTokenHex)", forKey: lastUploadedKey)
        } catch {
            print("Push device registration failed: \(error.localizedDescription)")
        }
        #endif
    }

    /// Clears cached upload state so the next token sync re-posts (e.g. after login).
    static func invalidateCachedRegistration() {
        UserDefaults.standard.removeObject(forKey: lastUploadedKey)
    }

    /// Re-uploads the last known APNs token after role / email / seller id changes.
    static func syncAfterIdentityChange() async {
        guard let hex = UserDefaults.standard.string(forKey: "pushRegistration.deviceTokenHex"),
              !hex.isEmpty else { return }
        invalidateCachedRegistration()
        await uploadTokenIfNeeded(hex)
    }

    private static func currentUserKeyForPush() -> String {
        let defaults = UserDefaults.standard
        let role = defaults.string(forKey: "userRole") ?? ""

        if role == "seller" {
            let id = defaults.string(forKey: "sellerSellerId")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !id.isEmpty {
                return "seller:\(id)"
            }
        }

        if defaults.bool(forKey: "buyerAccountCreated") {
            let email = defaults.string(forKey: "buyerEmail")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            if !email.isEmpty {
                return "buyer:\(email)"
            }
        }

        return GuestInstallIdentity.userKey
    }

    private static func postRegistration(_ body: RegisterPushDeviceRequest) async throws {
        let url = CheckoutAPI.baseURL.appendingPathComponent("register-push-device")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

private struct RegisterPushDeviceRequest: Encodable {
    let deviceToken: String
    let userKey: String
    let platform: String
    let bundleId: String
}
