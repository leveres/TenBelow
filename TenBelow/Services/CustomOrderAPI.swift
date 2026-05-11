import Foundation

// MARK: - Seller-facing models

struct SellerCustomOrderRequest: Identifiable, Codable, Hashable {
    enum Status: String, Codable, CaseIterable {
        case pending
        case accepted
        case declined
    }

    let id: String
    let sellerId: String
    let buyerName: String
    let buyerEmail: String
    let description: String
    let referenceImageURLs: [String]
    let createdAt: String
    let status: Status
    let statusUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, sellerId, buyerName, buyerEmail, description, referenceImageURLs, createdAt, status, statusUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sellerId = try c.decode(String.self, forKey: .sellerId)
        buyerName = try c.decode(String.self, forKey: .buyerName)
        buyerEmail = try c.decode(String.self, forKey: .buyerEmail)
        description = try c.decode(String.self, forKey: .description)
        referenceImageURLs = try c.decodeIfPresent([String].self, forKey: .referenceImageURLs) ?? []
        createdAt = try c.decode(String.self, forKey: .createdAt)
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .pending
        statusUpdatedAt = try c.decodeIfPresent(String.self, forKey: .statusUpdatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sellerId, forKey: .sellerId)
        try c.encode(buyerName, forKey: .buyerName)
        try c.encode(buyerEmail, forKey: .buyerEmail)
        try c.encode(description, forKey: .description)
        try c.encode(referenceImageURLs, forKey: .referenceImageURLs)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(statusUpdatedAt, forKey: .statusUpdatedAt)
    }
}

// MARK: - API

enum CustomOrderAPI {
    private static var baseURL: URL { CheckoutAPI.baseURL }

    private static func userFacingHTTPError(data: Data, statusCode: Int, fallback: String) -> NSError {
        if let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
            if s.hasPrefix("<!DOCTYPE") || s.localizedCaseInsensitiveContains("<html") {
                return NSError(
                    domain: "CustomOrderAPI",
                    code: statusCode,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The app reached a server that doesn’t provide custom orders. Use the full TenBelow marketplace API (TenBelow/tenbelow-backend), not the minimal Stripe-only server — see tenbelow-backend/README.md."
                    ]
                )
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let msg = obj["message"] as? String, !msg.isEmpty {
                    return NSError(domain: "CustomOrderAPI", code: statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
                }
                if let err = obj["error"] as? String, !err.isEmpty {
                    return NSError(domain: "CustomOrderAPI", code: statusCode, userInfo: [NSLocalizedDescriptionKey: err])
                }
            }
            if s.count < 400 {
                return NSError(domain: "CustomOrderAPI", code: statusCode, userInfo: [NSLocalizedDescriptionKey: s])
            }
        }
        return NSError(domain: "CustomOrderAPI", code: statusCode, userInfo: [NSLocalizedDescriptionKey: fallback])
    }

    private struct UploadResponse: Decodable {
        let url: String
    }

    private struct SubmitResponse: Decodable {
        let ok: Bool
    }

    /// Uploads one reference image; returns a path such as `/media/custom-order-ref/...`.
    static func uploadReferenceImage(
        sellerId: String,
        imageData: Data,
        fileExtension: String,
        contentType: String
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("custom-order-reference/\(sellerId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(fileExtension, forHTTPHeaderField: "X-File-Extension")
        AppConstants.applyAppClientAuth(to: &request)
        request.httpBody = imageData

        let (data, response) = try await URLSession.tenBelow.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? String {
                throw NSError(domain: "CustomOrderAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: err])
            }
            throw NSError(
                domain: "CustomOrderAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Upload failed"]
            )
        }
        return try JSONDecoder().decode(UploadResponse.self, from: data).url
    }

    static func submitRequest(
        sellerId: String,
        buyerName: String,
        buyerEmail: String,
        description: String,
        referenceImageURLs: [String]
    ) async throws {
        struct Body: Encodable {
            let sellerId: String
            let buyerName: String
            let buyerEmail: String
            let description: String
            let referenceImageURLs: [String]
        }

        let url = baseURL.appendingPathComponent("custom-order-requests")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(
            Body(
                sellerId: sellerId,
                buyerName: buyerName,
                buyerEmail: buyerEmail,
                description: description,
                referenceImageURLs: referenceImageURLs
            )
        )

        let (data, response) = try await URLSession.tenBelow.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? String {
                throw NSError(domain: "CustomOrderAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: err])
            }
            throw NSError(
                domain: "CustomOrderAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "Request failed"]
            )
        }
        _ = try JSONDecoder().decode(SubmitResponse.self, from: data)
    }

    // MARK: Seller

    private struct SellerCustomOrderListResponse: Decodable {
        let requests: [SellerCustomOrderRequest]
    }

    private struct SellerCustomOrderSingleResponse: Decodable {
        let request: SellerCustomOrderRequest
    }

    static func fetchSellerRequests(sellerId: String) async throws -> [SellerCustomOrderRequest] {
        let url = baseURL.appendingPathComponent("seller-custom-orders/\(sellerId)")
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)

        let (data, response) = try await URLSession.tenBelow.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw userFacingHTTPError(data: data, statusCode: http.statusCode, fallback: "Could not load requests")
        }
        return try JSONDecoder().decode(SellerCustomOrderListResponse.self, from: data).requests
    }

    static func updateSellerRequestStatus(requestId: String, status: SellerCustomOrderRequest.Status) async throws -> SellerCustomOrderRequest {
        let url = baseURL.appendingPathComponent("custom-order-request/\(requestId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)
        struct Body: Encodable {
            let status: String
        }
        request.httpBody = try JSONEncoder().encode(Body(status: status.rawValue))

        let (data, response) = try await URLSession.tenBelow.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? String {
                throw NSError(domain: "CustomOrderAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: err])
            }
            throw NSError(domain: "CustomOrderAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Update failed"])
        }
        return try JSONDecoder().decode(SellerCustomOrderSingleResponse.self, from: data).request
    }
}
