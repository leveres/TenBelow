import Foundation

enum DropAPI {

    private static var baseURL: URL { CheckoutAPI.baseURL }

    // MARK: - Submit a product to the weekly drop

    static func submitProduct(_ request: DropSubmissionRequest) async throws -> DropProduct {
        let url = baseURL.appendingPathComponent("drop/submit")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try validateResponse(data: data, resp: resp)
        return try JSONDecoder().decode(DropProduct.self, from: data)
    }

    // MARK: - Get the current active drop

    static func currentDrop() async throws -> CurrentDropResponse {
        let url = baseURL.appendingPathComponent("drop/current")
        let (data, resp) = try await URLSession.shared.data(from: url)
        try validateResponse(data: data, resp: resp)
        return try JSONDecoder().decode(CurrentDropResponse.self, from: data)
    }

    // MARK: - Get seller's submissions for this week

    static func mySubmissions(sellerId: String) async throws -> SellerSubmissionsResponse {
        let url = baseURL.appendingPathComponent("drop/my-submissions/\(sellerId)")
        let (data, resp) = try await URLSession.shared.data(from: url)
        try validateResponse(data: data, resp: resp)
        return try JSONDecoder().decode(SellerSubmissionsResponse.self, from: data)
    }

    // MARK: - Delete a submission

    static func deleteSubmission(productId: String) async throws {
        let url = baseURL.appendingPathComponent("drop/submission/\(productId)")
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"

        let (data, resp) = try await URLSession.shared.data(for: req)
        try validateResponse(data: data, resp: resp)
    }

    // MARK: - Shared validation

    private static func validateResponse(data: Data, resp: URLResponse) throws {
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "DropAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}
