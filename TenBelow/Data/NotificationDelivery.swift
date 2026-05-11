import Foundation

protocol NotificationDelivering {
    /// Local inbox already persists before this runs; keep implementations **idempotent** so replays are safe.
    /// When adding APNs (or other transports), handle retries/backoff here rather than in `NotificationStore`.
    func deliver(_ notification: AppNotification)
}

struct PushNotificationDeliveryBridge: NotificationDelivering {
    func deliver(_ notification: AppNotification) {
        // Push delivery is intentionally not wired yet.
        // This bridge exists so local inbox notifications and future remote push can stay separate.
        _ = notification
    }
}
