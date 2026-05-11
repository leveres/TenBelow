import Foundation

private struct BuyerAccountUpdateRequest: Encodable {
    let newEmail: String?
    let newPassword: String?
}

struct BuyerAccountUpdateResponse: Decodable {
    let ok: Bool
    let email: String
    let token: String
    let emailChanged: Bool
    let passwordChanged: Bool
    let confirmationTargets: [String]
}

enum BuyerAccountAPI {
    static func updateAccount(newEmail: String?, newPassword: String?) async throws -> BuyerAccountUpdateResponse {
        let url = CheckoutAPI.baseURL.appendingPathComponent("auth/buyer-account-update")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(
            BuyerAccountUpdateRequest(newEmail: newEmail, newPassword: newPassword)
        )

        let (data, response) = try await URLSession.tenBelow.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode(ServerErrorResponse.self, from: data).error)
                ?? String(data: data, encoding: .utf8)
                ?? "Server error"
            throw NSError(domain: "BuyerAccountAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        return try JSONDecoder().decode(BuyerAccountUpdateResponse.self, from: data)
    }
}

private struct ServerErrorResponse: Decodable {
    let error: String
}
