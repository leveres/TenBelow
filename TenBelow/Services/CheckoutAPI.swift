import Foundation

enum CheckoutAPI {
    /// Replace with your deployed backend URL (e.g. https://api.tenbelow.com)
    static let baseURL = URL(string: "http://localhost:3000")!

    static func createPaymentIntent(req: CreatePaymentIntentRequest) async throws -> CreatePaymentIntentResponse {
        let url = baseURL.appendingPathComponent("create-payment-intent")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(req)

        let (data, resp) = try await URLSession.shared.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "CheckoutAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(CreatePaymentIntentResponse.self, from: data)
    }
}
