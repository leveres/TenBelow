import Foundation

protocol NotificationDelivering {
    func deliver(_ notification: AppNotification)
}

struct PushNotificationDeliveryBridge: NotificationDelivering {
    func deliver(_ notification: AppNotification) {
        // Push delivery is intentionally not wired yet.
        // This bridge exists so local inbox notifications and future remote push can stay separate.
        _ = notification
    }
}
