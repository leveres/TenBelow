//
//  AppDelegate.swift
//  TenBelow
//

#if os(iOS)
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02hhx", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: "pushRegistration.deviceTokenHex")
        Task {
            await PushDeviceRegistration.uploadTokenIfNeeded(hex)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator often fails; real devices need Push capability + signed provisioning.
        #if DEBUG
        print("APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    /// Chooses a single presentation path for an incoming alert.
    ///
    /// Active: iOS suppresses its own banner and TenBelow draws the compact in-app banner, so
    /// the same event never appears twice. The alert still lands in Notification Center.
    /// Not active: iOS handles the alert normally and TenBelow draws nothing.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        MainActor.assumeIsolated {
            let content = notification.request.content
            let eventId = content.userInfo[NotificationPushPayload.eventIdKey] as? String
            let userId = NotificationStore.currentUserIdFromDefaults()

            guard UIApplication.shared.applicationState == .active else {
                // iOS shows the system banner; record identity so opening the app later does
                // not also draw a custom banner for the matching local event.
                NotificationBannerCenter.shared.acknowledgeRemoteDelivery(
                    eventId: eventId,
                    requestIdentifier: notification.request.identifier,
                    title: content.title,
                    body: content.body
                )
                completionHandler([.banner, .badge, .sound, .list])
                return
            }

            NotificationBannerCenter.shared.deliverForegroundPush(
                requestIdentifier: notification.request.identifier,
                title: content.title,
                body: content.body,
                userId: userId,
                eventId: eventId
            )
            completionHandler([.badge, .sound, .list])
        }
    }

    static func ensureNotificationsAuthorizedIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        do {
            let settings = await center.notificationSettings()

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            case .notDetermined:
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                guard granted else { return }
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            case .denied:
                return
            @unknown default:
                return
            }
        } catch {
            #if DEBUG
            print("Notification authorization error: \(error.localizedDescription)")
            #endif
        }
    }
}
#endif
