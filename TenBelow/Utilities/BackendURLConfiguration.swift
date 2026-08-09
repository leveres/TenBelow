import Foundation

/// Backend base URL resolution safe to call from nonisolated media/network code paths.
enum BackendURLConfiguration {
    private nonisolated static let backendBaseURLInfoKey = "TENBELOW_BACKEND_BASE_URL"
    nonisolated static let debugBackendBaseURLOverrideKey = "tb.debugBackendBaseURLOverride"

    #if DEBUG
    nonisolated(unsafe) private static var debugOverrideSnapshot: String?

    @MainActor
    static func refreshDebugOverrideCache() {
        let rawValue = configurationValue(for: backendBaseURLInfoKey)
        let stored = UserDefaults.standard.string(forKey: debugBackendBaseURLOverrideKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let stored, !stored.isEmpty, let url = validBackendURL(from: stored) else {
            debugOverrideSnapshot = nil
            return
        }

        if shouldIgnoreDebugOverride(url, configuredBackendValue: rawValue) {
            UserDefaults.standard.removeObject(forKey: debugBackendBaseURLOverrideKey)
            debugOverrideSnapshot = nil
        } else {
            debugOverrideSnapshot = stored
        }
    }
    #endif

    nonisolated static func baseURL() -> URL? {
        let rawValue = configurationValue(for: backendBaseURLInfoKey)
        #if DEBUG
        if let override = debugOverrideSnapshot,
           !override.isEmpty,
           let url = validBackendURL(from: override),
           !shouldIgnoreDebugOverride(url, configuredBackendValue: rawValue) {
            return url
        }
        #endif
        return validBackendURL(from: rawValue)
    }

    nonisolated private static func validBackendURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !isPlaceholderConfigurationValue(trimmed),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }

        #if !DEBUG
        guard scheme == "https" else { return nil }
        if let host = url.host?.lowercased(),
           host == "localhost" || host == "127.0.0.1" {
            return nil
        }
        #endif

        return url
    }

    #if DEBUG
    nonisolated private static func shouldIgnoreDebugOverride(_ overrideURL: URL, configuredBackendValue: String) -> Bool {
        guard configuredBackendValue.contains("tenbelow.onrender.com") else { return false }
        return overrideURL.scheme?.lowercased() != "https"
    }
    #endif

    nonisolated private static func configurationValue(for key: String) -> String {
        String(Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func isPlaceholderConfigurationValue(_ value: String) -> Bool {
        let normalized = value.uppercased()
        return normalized.contains("YOUR_")
            || normalized.contains("PLACEHOLDER")
            || normalized.contains("REPLACE_ME")
    }
}
