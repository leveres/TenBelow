import Foundation

enum NotificationType: String, Codable, Hashable, CaseIterable {
    case priceDrop
    case newProduct
    case orderReceived
    case orderStatusUpdate
    case itemFavorited
    case system
}

struct AppNotification: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    let type: NotificationType
    let title: String
    let message: String
    let relatedProductId: String?
    let relatedOrderId: String?
    let relatedSellerId: String?
    var isRead: Bool
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        userId: String,
        type: NotificationType,
        title: String,
        message: String,
        relatedProductId: String? = nil,
        relatedOrderId: String? = nil,
        relatedSellerId: String? = nil,
        isRead: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.userId = userId
        self.type = type
        self.title = title
        self.message = message
        self.relatedProductId = relatedProductId
        self.relatedOrderId = relatedOrderId
        self.relatedSellerId = relatedSellerId
        self.isRead = isRead
        self.createdAt = createdAt
    }
}

// MARK: - In-app notification preferences (UserDefaults, default on)

enum NotificationPreferences {
    private static func storageKey(for type: NotificationType) -> String {
        "tenBelow.notifications.pref.\(type.rawValue)"
    }

    /// `true` when the user has not changed the default (notifications allowed).
    static func isTypeEnabled(_ type: NotificationType) -> Bool {
        let key = storageKey(for: type)
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func appStorageKey(for type: NotificationType) -> String {
        storageKey(for: type)
    }
}
