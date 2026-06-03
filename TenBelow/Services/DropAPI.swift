import Foundation

private struct DropAPIServerError: Decodable {
    let error: String
}

struct DropAPIError: LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? { message }

    var isSellerSessionRequired: Bool {
        guard statusCode == 401 else { return false }
        let lower = message.lowercased()
        return lower.contains("seller session")
            || lower.contains("authenticated seller")
            || lower.contains("sign in")
    }
}

enum DropAPI {

    private static var baseURL: URL { CheckoutAPI.baseURL }

    // MARK: - Submit a product to the weekly drop

    static func submitProduct(_ request: DropSubmissionRequest) async throws -> DropProduct {
        let url = baseURL.appendingPathComponent("drop/submit")
        let (data, _) = try await performSellerAuthorizedRequest {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(request)
            return req
        }
        return try JSONDecoder().decode(DropProduct.self, from: data)
    }

    // MARK: - Update an existing weekly drop submission

    static func updateSubmission(productId: String, request: DropSubmissionRequest) async throws -> DropProduct {
        let url = baseURL.appendingPathComponent("drop/submission/\(productId)")
        let (data, _) = try await performSellerAuthorizedRequest {
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(request)
            return req
        }
        return try JSONDecoder().decode(DropProduct.self, from: data)
    }

    // MARK: - Get the current active drop

    static func currentDrop() async throws -> CurrentDropResponse {
        let url = baseURL.appendingPathComponent("drop/current")
        var req = URLRequest(url: url)
        AppConstants.applyAppClientAuth(to: &req)
        let (data, resp) = try await URLSession.tenBelow.data(for: req)
        try validateResponse(data: data, resp: resp)
        return try JSONDecoder().decode(CurrentDropResponse.self, from: data)
    }

    // MARK: - Get seller's submissions for this week

    static func mySubmissions(sellerId: String) async throws -> SellerSubmissionsResponse {
        let url = baseURL.appendingPathComponent("drop/my-submissions/\(sellerId)")
        let (data, _) = try await performSellerAuthorizedRequest {
            URLRequest(url: url)
        }
        return try JSONDecoder().decode(SellerSubmissionsResponse.self, from: data)
    }

    // MARK: - Get seller's previous weekly drop history

    static func history(sellerId: String) async throws -> SellerDropHistoryResponse {
        let url = baseURL.appendingPathComponent("drop/history/\(sellerId)")
        let (data, _) = try await performSellerAuthorizedRequest {
            URLRequest(url: url)
        }
        return try JSONDecoder().decode(SellerDropHistoryResponse.self, from: data)
    }

    // MARK: - Delete a submission

    static func deleteSubmission(productId: String) async throws {
        let url = baseURL.appendingPathComponent("drop/submission/\(productId)")
        _ = try await performSellerAuthorizedRequest {
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            return req
        }
    }

    // MARK: - Shared validation

    private static func serverErrorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(DropAPIServerError.self, from: data) {
            return decoded.error
        }
        return String(data: data, encoding: .utf8) ?? "Server error"
    }

    private static func mapSessionError(_ error: Error) -> Error {
        if let sessionError = error as? MarketplaceAuthSessionError {
            return DropAPIError(statusCode: 401, message: sessionError.localizedDescription)
        }
        return error
    }

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

        func failure(from data: Data, statusCode: Int) -> DropAPIError {
            DropAPIError(statusCode: statusCode, message: serverErrorMessage(from: data))
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

    private static func validateResponse(data: Data, resp: URLResponse) throws {
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DropAPIError(statusCode: http.statusCode, message: serverErrorMessage(from: data))
        }
    }
}
