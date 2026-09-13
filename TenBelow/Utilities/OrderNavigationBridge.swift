import Foundation

/// Cross-tab deep link into Orders (e.g. seller taps "New order received").
enum OrderNavigationBridge {
    static let pendingOrderIdKey = "tb.pendingOrderNavigationId"
    static let ordersTabIndex = 3

    static func requestOpenOrder(orderId: String) {
        let trimmed = orderId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        TabLaunchBridge.requestTab(ordersTabIndex)
        UserDefaults.standard.set(trimmed, forKey: pendingOrderIdKey)
    }

    static func consumePendingOrderId() -> String? {
        let trimmed = String(UserDefaults.standard.string(forKey: pendingOrderIdKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingOrderIdKey)
        return trimmed
    }
}
