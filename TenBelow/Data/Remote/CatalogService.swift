import Foundation

struct CatalogLoadResult {
    let products: [RemoteProduct]
    let isFromRemote: Bool
}

enum CatalogService {
    private static var catalogURL: URL {
        CheckoutAPI.baseURL.appendingPathComponent("catalog")
    }

    /// Fetch → Cache → Fallback. Returns whether data came from the live server.
    static func loadProducts() async -> CatalogLoadResult {
        // 1. Try remote
        if AppConstants.isBackendConfigured {
            if let response = try? await URLSession.tenBelow.decode(
                CatalogResponse.self,
                from: catalogURL
            ) {
                CacheStore.save(response, to: AppConstants.catalogCacheFile)
                return CatalogLoadResult(products: response.products, isFromRemote: true)
            }
        }

        // 2. Try disk cache
        if let cached = CacheStore.load(
            CatalogResponse.self,
            from: AppConstants.catalogCacheFile
        ) {
            return CatalogLoadResult(products: cached.products, isFromRemote: false)
        }

        // 3. Bundle fallback
        if let fallback = CacheStore.loadFromBundle(
            CatalogResponse.self,
            resource: AppConstants.catalogFallbackFile
        ) {
            return CatalogLoadResult(products: fallback.products, isFromRemote: false)
        }

        return CatalogLoadResult(products: [], isFromRemote: false)
    }
}
