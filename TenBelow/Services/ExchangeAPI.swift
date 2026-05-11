import Foundation

private struct ExchangeEligibilityRequestBody: Encodable {
    let orderId: String
    let orderItemId: String
    let requestedResolution: String
}

private struct ExchangeEligibilityResponse: Decodable {
    let result: ExchangeEligibilityResult
}

private struct CreateExchangeRequestBody: Encodable {
    let orderId: String
    let orderItemId: String
    let reasonCode: String
    let buyerExplanation: String
    let requestedResolution: String
    let originalVariantSnapshot: [String: String]
}

private struct ExchangeRequestEnvelope: Decodable {
    let exchangeRequest: ExchangeRequest
}

private struct OrderExchangeRequestsEnvelope: Decodable {
    let exchangeRequests: [ExchangeRequest]
}

private struct ExchangeProofUploadEnvelope: Decodable {
    let exchangeRequest: ExchangeRequest
    let asset: ExchangeProofAsset
}

struct ExchangeProofUploadResult {
    let exchangeRequest: ExchangeRequest
    let asset: ExchangeProofAsset
}

enum ExchangeAPI {
    private static var baseURL: URL { CheckoutAPI.baseURL }

    static func checkEligibility(
        orderId: String,
        orderItemId: String,
        requestedResolution: ExchangeRequestedResolution = .sameItemExchange
    ) async throws -> ExchangeEligibilityResult {
        try await performJSONRequest(
            path: "exchange-requests/eligibility-check",
            method: "POST",
            body: ExchangeEligibilityRequestBody(
                orderId: orderId,
                orderItemId: orderItemId,
                requestedResolution: requestedResolution.rawValue
            ),
            responseType: ExchangeEligibilityResponse.self
        ).result
    }

    static func createRequest(
        orderId: String,
        orderItemId: String,
        reasonCode: ExchangeReasonCode,
        buyerExplanation: String,
        requestedResolution: ExchangeRequestedResolution = .sameItemExchange,
        originalVariantSnapshot: [String: String] = [:]
    ) async throws -> ExchangeRequest {
        try await performJSONRequest(
            path: "exchange-requests",
            method: "POST",
            body: CreateExchangeRequestBody(
                orderId: orderId,
                orderItemId: orderItemId,
                reasonCode: reasonCode.rawValue,
                buyerExplanation: buyerExplanation,
                requestedResolution: requestedResolution.rawValue,
                originalVariantSnapshot: originalVariantSnapshot
            ),
            responseType: ExchangeRequestEnvelope.self
        ).exchangeRequest
    }

    static func uploadProof(
        exchangeRequestId: String,
        asset: ExchangeLocalDraftAsset,
        videoDurationSeconds: Int? = nil
    ) async throws -> ExchangeProofUploadResult {
        guard let localFileURL = asset.localFileURL else {
            throw NSError(
                domain: "ExchangeAPI",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "We couldn't read that proof file."]
            )
        }

        let data = try Data(contentsOf: localFileURL)
        let url = baseURL
            .appendingPathComponent("exchange-requests")
            .appendingPathComponent(exchangeRequestId)
            .appendingPathComponent("proof")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(asset.type == .video ? "video/mp4" : "image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue(asset.type.rawValue, forHTTPHeaderField: "X-Proof-Type")
        request.setValue(localFileURL.pathExtension.isEmpty ? (asset.type == .video ? "mp4" : "jpg") : localFileURL.pathExtension, forHTTPHeaderField: "X-File-Extension")
        if let videoDurationSeconds {
            request.setValue("\(videoDurationSeconds)", forHTTPHeaderField: "X-Video-Duration-Seconds")
        }
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)

        let (responseData, response) = try await URLSession.tenBelow.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw apiError(from: responseData, statusCode: http.statusCode)
        }

        let decoded = try makeDecoder().decode(ExchangeProofUploadEnvelope.self, from: responseData)
        return ExchangeProofUploadResult(exchangeRequest: decoded.exchangeRequest, asset: decoded.asset)
    }

    static func fetchRequest(id: String) async throws -> ExchangeRequest {
        try await URLSession.tenBelow
            .decode(
                ExchangeRequestEnvelope.self,
                from: baseURL.appendingPathComponent("exchange-requests").appendingPathComponent(id)
            )
            .exchangeRequest
    }

    static func fetchRequests(orderId: String) async throws -> [ExchangeRequest] {
        try await URLSession.tenBelow
            .decode(
                OrderExchangeRequestsEnvelope.self,
                from: baseURL
                    .appendingPathComponent("orders")
                    .appendingPathComponent(orderId)
                    .appendingPathComponent("exchange-requests")
            )
            .exchangeRequests
    }

    static func cancelRequest(id: String) async throws -> ExchangeRequest {
        try await performJSONRequest(
            path: "exchange-requests/\(id)/cancel",
            method: "POST",
            body: EmptyExchangeRequestBody(),
            responseType: ExchangeRequestEnvelope.self
        ).exchangeRequest
    }

    private static func performJSONRequest<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body,
        responseType: Response.Type
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.tenBelow.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw apiError(from: data, statusCode: http.statusCode)
        }
        return try makeDecoder().decode(responseType, from: data)
    }

    private static func apiError(from data: Data, statusCode: Int) -> NSError {
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            ?? String(data: data, encoding: .utf8)
            ?? "Server error"
        return NSError(
            domain: "ExchangeAPI",
            code: statusCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct EmptyExchangeRequestBody: Encodable {}
