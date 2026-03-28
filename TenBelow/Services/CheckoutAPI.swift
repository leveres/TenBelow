import Foundation

struct CheckoutAPIError: LocalizedError {
    let code: String?
    let message: String

    var errorDescription: String? {
        message
    }
}

enum CheckoutAPI {
    /// Reads the configured backend URL from the generated Info.plist.
    /// Falls back to a reserved invalid host so non-checkout callers fail safely instead of crashing.
    static var baseURL: URL {
        AppConstants.backendBaseURL ?? URL(string: "https://tenbelow.invalid")!
    }

    static func createPaymentIntent(req: CreatePaymentIntentRequest) async throws -> CreatePaymentIntentResponse {
        guard let baseURL = AppConstants.backendBaseURL else {
            throw CheckoutAPIError(code: "configuration_error", message: AppConstants.checkoutSetupMessage)
        }
        let url = baseURL.appendingPathComponent("create-payment-intent")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(req)

        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if let serverError = try? JSONDecoder().decode(CheckoutAPIErrorResponse.self, from: data) {
                throw CheckoutAPIError(code: serverError.code, message: serverError.error)
            }

            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw CheckoutAPIError(code: "server_error", message: msg)
        }
        return try JSONDecoder().decode(CreatePaymentIntentResponse.self, from: data)
    }
}
