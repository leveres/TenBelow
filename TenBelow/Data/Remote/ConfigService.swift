import Foundation

enum ConfigService {
    private static var configURL: URL {
        CheckoutAPI.baseURL.appendingPathComponent("config")
    }

    /// Fetch → Cache → Fallback
    static func loadConfig() async -> AppConfig {
        // 1. Try remote
        if AppConstants.isBackendConfigured {
            if let remote = try? await URLSession.tenBelow.decode(
                AppConfig.self,
                from: configURL
            ) {
                CacheStore.save(remote, to: AppConstants.configCacheFile)
                return remote
            }
        }

        // 2. Try disk cache
        if let cached = CacheStore.load(
            AppConfig.self,
            from: AppConstants.configCacheFile
        ) {
            return cached
        }

        // 3. Bundle fallback
        if let fallback = CacheStore.loadFromBundle(
            AppConfig.self,
            resource: AppConstants.configFallbackFile
        ) {
            return fallback
        }

        // 4. Hardcoded default
        return .default
    }
}
