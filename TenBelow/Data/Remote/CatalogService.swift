import Foundation

enum CatalogService {

    /// Fetch → Cache → Fallback
    static func loadProducts() async -> [RemoteProduct] {

        // 1. Try remote
        if let response = try? await URLSession.shared.decode(
            CatalogResponse.self,
            from: AppConstants.catalogURL
        ) {
            CacheStore.save(response, to: AppConstants.catalogCacheFile)
            return response.products
        }

        // 2. Try disk cache
        if let cached = CacheStore.load(
            CatalogResponse.self,
            from: AppConstants.catalogCacheFile
        ) {
            return cached.products
        }

        // 3. Bundle fallback
        if let fallback = CacheStore.loadFromBundle(
            CatalogResponse.self,
            resource: AppConstants.catalogFallbackFile
        ) {
            return fallback.products
        }

        return []
    }
}
