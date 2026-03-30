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
        print("APNs registration failed: \(error.localizedDescription)")
    }

    /// Show banner/sound when a push arrives while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
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
            print("Notification authorization error: \(error.localizedDescription)")
        }
    }
}
#endif
