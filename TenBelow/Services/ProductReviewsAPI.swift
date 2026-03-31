import Foundation

private struct SubmitProductReviewRequest: Codable {
    let orderId: String
    let productId: String
    let buyerEmail: String
    let rating: Int
    let reviewText: String?
}

struct SubmitProductReviewResponse: Codable {
    let ok: Bool
    let productId: String
    let averageRating: Double
    let reviewCount: Int
}

struct ProductReview: Codable, Identifiable, Hashable {
    let id: String
    let orderId: String
    let productId: String
    let sellerId: String?
    let buyerEmail: String
    let rating: Int
    let reviewText: String?
    let createdAt: Date
    let updatedAt: Date
}

struct ProductReviewsResponse: Codable {
    let productId: String
    let averageRating: Double
    let reviewCount: Int
    let reviews: [ProductReview]
}

enum ProductReviewsAPI {
    static func submitReview(
        orderId: String,
        productId: String,
        buyerEmail: String,
        rating: Int,
        reviewText: String?
    ) async throws -> SubmitProductReviewResponse {
        let url = CheckoutAPI.baseURL.appendingPathComponent("product-reviews")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SubmitProductReviewRequest(
                orderId: orderId,
                productId: productId,
                buyerEmail: buyerEmail,
                rating: rating,
                reviewText: reviewText
            )
        )

        let (data, resp) = try await URLSession.tenBelow.data(for: request)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if let serverError = try? JSONDecoder().decode(CheckoutAPIErrorResponse.self, from: data) {
                throw CheckoutAPIError(code: serverError.code, message: serverError.error)
            }

            let message = String(data: data, encoding: .utf8) ?? "Server error"
            throw CheckoutAPIError(code: "server_error", message: message)
        }

        return try JSONDecoder().decode(SubmitProductReviewResponse.self, from: data)
    }

    static func fetchReviews(for productId: String) async throws -> ProductReviewsResponse {
        var components = URLComponents(url: CheckoutAPI.baseURL.appendingPathComponent("product-reviews"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "productId", value: productId),
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        return try await URLSession.tenBelow.decode(ProductReviewsResponse.self, from: url)
    }
}
