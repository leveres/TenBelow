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

enum OrdersAPI {
    private static var baseURL: URL { CheckoutAPI.baseURL }

    static func fetchBuyerOrders(email: String) async throws -> [Order] {
        var components = URLComponents(url: baseURL.appendingPathComponent("orders"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "buyerEmail", value: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        return try await URLSession.tenBelow.decode(OrdersResponse.self, from: url).orders
    }

    static func fetchSellerOrders(sellerId: String) async throws -> [Order] {
        var components = URLComponents(url: baseURL.appendingPathComponent("orders"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "sellerId", value: sellerId.trimmingCharacters(in: .whitespacesAndNewlines))
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        return try await URLSession.tenBelow.decode(OrdersResponse.self, from: url).orders
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
}
