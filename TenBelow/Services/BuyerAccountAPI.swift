import Foundation

private struct BuyerAccountCreateRequest: Encodable {
    let email: String
    let fullName: String
    let password: String
}

private struct BuyerAccountUpdateRequest: Encodable {
    let newEmail: String?
    let newPassword: String?
}

private struct BuyerLoginRequest: Encodable {
    let email: String
    let password: String
}

struct BuyerLoginResponse: Decodable {
    let token: String
    let role: String
    let buyerEmail: String
    let fullName: String?
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
    static func createAccount(fullName: String, email: String, password: String) async throws {
        let url = CheckoutAPI.baseURL.appendingPathComponent("auth/buyer-account")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(
            BuyerAccountCreateRequest(email: email, fullName: fullName, password: password)
        )

        let (data, response) = try await URLSession.tenBelow.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw apiError(from: data, statusCode: http.statusCode)
        }
    }

    static func login(email: String, password: String) async throws -> BuyerLoginResponse {
        let url = CheckoutAPI.baseURL.appendingPathComponent("auth/buyer-login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(
            BuyerLoginRequest(email: email, password: password)
        )

        let (data, response) = try await URLSession.tenBelow.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw apiError(from: data, statusCode: http.statusCode)
        }

        return try JSONDecoder().decode(BuyerLoginResponse.self, from: data)
    }

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
            throw apiError(from: data, statusCode: http.statusCode)
        }

        return try JSONDecoder().decode(BuyerAccountUpdateResponse.self, from: data)
    }

    private static func apiError(from data: Data, statusCode: Int) -> NSError {
        let message = (try? JSONDecoder().decode(ServerErrorResponse.self, from: data).error)
            ?? String(data: data, encoding: .utf8)
            ?? "Server error"
        return NSError(domain: "BuyerAccountAPI", code: statusCode, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private struct ServerErrorResponse: Decodable {
    let error: String
}
