import Foundation

/// Cross-tab navigation that always fires, even when the target tab index is unchanged.
enum TabLaunchBridge {
    static let pendingLaunchTabKey = "pendingLaunchTab"
    static let pendingLaunchTabTokenKey = "pendingLaunchTabToken"

    static func requestTab(_ index: Int) {
        UserDefaults.standard.set(index, forKey: pendingLaunchTabKey)
        UserDefaults.standard.set(UUID().uuidString, forKey: pendingLaunchTabTokenKey)
    }
}
