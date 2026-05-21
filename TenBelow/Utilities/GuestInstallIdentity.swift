import Foundation

/// Opaque per-install guest identity (`guest:<uuid>`) for analytics, inbox, engagement, and push registration.
/// Avoids sharing a single global `"guest"` bucket on the backend across all devices.
enum GuestInstallIdentity {
    private static let storageKey = "TenBelow.guestInstallOpaqueId"

    static var userKey: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: storageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return "guest:\(existing)"
        }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: storageKey)
        return "guest:\(fresh)"
    }
}
