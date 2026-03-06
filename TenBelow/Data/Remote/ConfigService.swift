import Foundation

enum ConfigService {

    /// Fetch → Cache → Fallback
    static func loadConfig() async -> AppConfig {

        // 1. Try remote
        if let remote = try? await URLSession.shared.decode(
            AppConfig.self,
            from: AppConstants.configURL
        ) {
            CacheStore.save(remote, to: AppConstants.configCacheFile)
            return remote
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
