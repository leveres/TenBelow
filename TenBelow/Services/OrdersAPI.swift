import Foundation

private struct OrdersResponse: Codable {
    let orders: [Order]
}

private struct ShipmentActionRequest: Codable {
    let orderId: String
    let shipmentId: String
    let sellerId: String
    let action: String
    let carrier: String?
    let trackingNumber: String?
}

private struct ShipmentActionResponse: Codable {
    let order: Order
}

private struct OrderProductionPreviewUpdateRequest: Codable {
    let orderId: String
    let shipmentId: String
    let sellerId: String
    let orderItemId: String
    let productionPreviewURL: String?
    let removeProductionPreview: Bool
}

private struct BuyerOrdersLookupRequest: Encodable {
    let buyerEmail: String
    let orderId: String?

    init(buyerEmail: String, orderId: String? = nil) {
        self.buyerEmail = buyerEmail
        self.orderId = orderId
    }
}

enum OrdersAPI {
    private static var baseURL: URL { CheckoutAPI.baseURL }

    static func fetchBuyerOrders(email: String) async throws -> [Order] {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }

        let url = baseURL.appendingPathComponent("orders/buyer")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(BuyerOrdersLookupRequest(buyerEmail: normalized))

        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "OrdersAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OrdersResponse.self, from: data).orders
    }

    static func fetchSellerOrders(sellerId: String) async throws -> [Order] {
        var components = URLComponents(url: baseURL.appendingPathComponent("orders"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "sellerId", value: sellerId.trimmingCharacters(in: .whitespacesAndNewlines))
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)

        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "OrdersAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OrdersResponse.self, from: data).orders
    }

    static func performShipmentAction(
        _ action: SellerShipmentAction,
        orderId: String,
        shipmentId: String,
        sellerId: String,
        carrier: String? = nil,
        trackingNumber: String? = nil
    ) async throws -> Order {
        let url = baseURL.appendingPathComponent("orders/shipment-action")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(
            ShipmentActionRequest(
                orderId: orderId,
                shipmentId: shipmentId,
                sellerId: sellerId,
                action: action.rawValue,
                carrier: carrier,
                trackingNumber: trackingNumber
            )
        )

        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "OrdersAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ShipmentActionResponse.self, from: data).order
    }

    static func updateOrderProductionPreview(
        orderId: String,
        shipmentId: String,
        sellerId: String,
        orderItemId: String,
        productionPreviewURL: String?,
        removeProductionPreview: Bool = false
    ) async throws -> Order {
        let url = baseURL.appendingPathComponent("orders/production-preview")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(
            OrderProductionPreviewUpdateRequest(
                orderId: orderId,
                shipmentId: shipmentId,
                sellerId: sellerId,
                orderItemId: orderItemId,
                productionPreviewURL: productionPreviewURL,
                removeProductionPreview: removeProductionPreview
            )
        )

        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "OrdersAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ShipmentActionResponse.self, from: data).order
    }

    private static func authorizedJSONRequest(path: String, method: String, body: Encodable? = nil) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
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

    private static func decodeOrderResponse(data: Data, resp: URLResponse) throws -> Order {
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Server error"
            throw NSError(domain: "OrdersAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ShipmentActionResponse.self, from: data).order
    }

    static func createSupportRequest(
        orderId: String,
        type: OrderSupportRequestType,
        sellerId: String,
        shipmentId: String,
        reason: String
    ) async throws -> Order {
        struct Body: Encodable {
            let type: String
            let sellerId: String
            let shipmentId: String
            let reason: String
        }
        let request = try authorizedJSONRequest(
            path: "orders/\(orderId)/support-requests",
            method: "POST",
            body: Body(type: type.rawValue, sellerId: sellerId, shipmentId: shipmentId, reason: reason)
        )
        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        return try decodeOrderResponse(data: data, resp: resp)
    }

    static func uploadSupportEvidence(
        orderId: String,
        requestId: String,
        data: Data,
        contentType: String,
        fileExtension: String,
        proofType: String
    ) async throws -> Order {
        let url = baseURL.appendingPathComponent("orders/\(orderId)/support-requests/\(requestId)/evidence")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(fileExtension, forHTTPHeaderField: "X-File-Extension")
        request.setValue(proofType, forHTTPHeaderField: "X-Proof-Type")
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)
        request.httpBody = data
        let (responseData, resp) = try await URLSession.tenBelow.data(for: request)
        return try decodeOrderResponse(data: responseData, resp: resp)
    }

    static func updateSupportRequest(
        orderId: String,
        requestId: String,
        status: OrderSupportRequestStatus,
        resolutionNote: String?
    ) async throws -> Order {
        struct Body: Encodable {
            let status: String
            let resolutionNote: String?
        }
        let request = try authorizedJSONRequest(
            path: "orders/\(orderId)/support-requests/\(requestId)",
            method: "PATCH",
            body: Body(status: status.rawValue, resolutionNote: resolutionNote)
        )
        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        return try decodeOrderResponse(data: data, resp: resp)
    }

    static func fetchSupportThread(orderId: String, sellerId: String) async throws -> [OrderSupportMessage] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("orders/\(orderId)/support-thread"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "sellerId", value: sellerId)]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)

        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = APIErrorMessage.userFacingHTTP(data: data, statusCode: http.statusCode)
            throw NSError(domain: "OrdersAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OrderSupportThreadResponse.self, from: data).messages
    }

    static func sendSupportMessage(
        orderId: String,
        sellerId: String,
        text: String,
        senderName: String?
    ) async throws -> OrderSupportMessagePostResponse {
        struct Body: Encodable {
            let sellerId: String
            let text: String
            let senderName: String?
        }
        let request = try authorizedJSONRequest(
            path: "orders/\(orderId)/support-thread",
            method: "POST",
            body: Body(sellerId: sellerId, text: text, senderName: senderName)
        )
        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = APIErrorMessage.userFacingHTTP(data: data, statusCode: http.statusCode)
            throw NSError(domain: "OrdersAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OrderSupportMessagePostResponse.self, from: data)
    }
}
