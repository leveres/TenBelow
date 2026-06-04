import Foundation

enum SellerInquiryAPI {
    private static var baseURL: URL { CheckoutAPI.baseURL }

    private static func authorizedJSONRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil
    ) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if let queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    private static func decode<T: Decodable>(_ type: T.Type, data: Data, resp: URLResponse) throws -> T {
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = APIErrorMessage.userFacingHTTP(data: data, statusCode: http.statusCode)
            throw NSError(domain: "SellerInquiryAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    static func fetchBuyerThreads() async throws -> [SellerInquiryThread] {
        let request = try authorizedJSONRequest(path: "buyer/inquiry-threads")
        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        return try decode(SellerInquiryThreadListResponse.self, data: data, resp: resp).threads
    }

    static func fetchSellerThreads() async throws -> [SellerInquiryThread] {
        let request = try authorizedJSONRequest(path: "seller/inquiry-threads")
        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        return try decode(SellerInquiryThreadListResponse.self, data: data, resp: resp).threads
    }

    static func fetchThread(sellerId: String, buyerEmail: String? = nil) async throws -> [OrderSupportMessage] {
        var query: [URLQueryItem] = []
        if let buyerEmail, !buyerEmail.isEmpty {
            query.append(URLQueryItem(name: "buyerEmail", value: buyerEmail))
        }
        let request = try authorizedJSONRequest(
            path: "sellers/\(sellerId)/inquiry-thread",
            queryItems: query.isEmpty ? nil : query
        )
        let (data, resp) = try await URLSession.tenBelow.data(for: request)

        if buyerEmail != nil {
            let payload = try decode(SellerInquirySellerLookupResponse.self, data: data, resp: resp)
            return payload.messages
        }
        let payload = try decode(SellerInquiryThreadResponse.self, data: data, resp: resp)
        return payload.messages
    }

    static func sendMessage(
        sellerId: String,
        text: String,
        senderName: String?,
        buyerEmail: String? = nil
    ) async throws -> [OrderSupportMessage] {
        struct Body: Encodable {
            let text: String
            let senderName: String?
            let buyerEmail: String?
        }
        let request = try authorizedJSONRequest(
            path: "sellers/\(sellerId)/inquiry-thread",
            method: "POST",
            body: Body(text: text, senderName: senderName, buyerEmail: buyerEmail)
        )
        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        return try decode(SellerInquiryMessagePostResponse.self, data: data, resp: resp).messages
    }
}
