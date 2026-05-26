import Foundation

extension URLSession {
    /// Shared session for storefront/API JSON. Marked `nonisolated` so callers (and default parameters like
    /// `CatalogService.loadProducts(urlSession:)`) are valid under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
    /// `URLSession` is thread-safe for concurrent `data`/`decode` tasks on this configuration.
    nonisolated static let tenBelow: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "tenbelow-url-cache"
        )
        return URLSession(configuration: config)
    }()

    nonisolated func decode<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.cachePolicy = cachePolicy
        if cachePolicy == .reloadIgnoringLocalCacheData {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)
        let (data, response) = try await data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
