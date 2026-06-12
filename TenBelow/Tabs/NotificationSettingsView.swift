//
//  NotificationSettingsView.swift
//

import SwiftUI
#if os(iOS)
import UserNotifications
#endif

struct NotificationSettingsView: View {
    @AppStorage("userRole") private var userRole = "buyer"
    @State private var externalAlertStatus = "Not checked yet"
    @State private var isEnablingExternalAlerts = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                externalAlertsSection
                notificationSettingsSection
                deliveryBehaviorSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .background(TBFrostBackground())
        .task {
            await refreshExternalAlertStatus()
        }
    }

    private var externalAlertsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iPhone alerts")
                .font(.tbHeadline)
                .foregroundStyle(TBTheme.icyBlue)

            Text("Allow TenBelow to show lock-screen, banner, sound, and Notification Center alerts for important buyer and seller activity.")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await enableExternalAlerts() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge.fill")
                    Text(isEnablingExternalAlerts ? "Enabling iPhone alerts..." : "Enable iPhone alerts")
                    Spacer()
                    if isEnablingExternalAlerts {
                        ProgressView()
                            .controlSize(.small)
                            .tint(TBTheme.deepSky)
                    }
                }
                .font(.tbBodyStrong)
                .foregroundStyle(TBTheme.deepSky)
                .padding(14)
                .background(TBTheme.skyLight.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isEnablingExternalAlerts)

            Button {
                Task { await sendTestAlert() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperplane.fill")
                    Text("Send test alert")
                    Spacer()
                }
                .font(.tbCaption)
                .foregroundStyle(TBTheme.icyBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isEnablingExternalAlerts)

            Text(externalAlertStatus)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 1)
        )
    }

    private var notificationSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Notification types")
                    .font(.tbHeadline)
                    .foregroundStyle(TBTheme.icyBlue)
                Spacer(minLength: 12)
                Text("\(enabledTypeCount)/\(roleNotificationTypes.count) on")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
            }

            Text("Choose which in-app alerts you want. You can change these anytime.")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                actionButton(title: "Enable all") { setAllTypesEnabled(true) }
                actionButton(title: "Disable all") { setAllTypesEnabled(false) }
            }

            VStack(spacing: 0) {
                if userRole == "seller" {
                    NotificationTypeToggle(
                        type: .orderReceived,
                        title: "New orders",
                        subtitle: "When a buyer places an order for your listings."
                    )
                    Divider().padding(.leading, 4)
                    NotificationTypeToggle(
                        type: .orderSupportUpdate,
                        title: "Buyer requests & messages",
                        subtitle: "Cancel/refund requests and order support thread messages."
                    )
                    Divider().padding(.leading, 4)
                    NotificationTypeToggle(
                        type: .itemFavorited,
                        title: "Listing favorites",
                        subtitle: "When someone saves one of your products."
                    )
                    Divider().padding(.leading, 4)
                    NotificationTypeToggle(
                        type: .system,
                        title: "Reminders & to-dos",
                        subtitle: "Operational reminders, such as updating order status."
                    )
                } else {
                    NotificationTypeToggle(
                        type: .priceDrop,
                        title: "Price drops",
                        subtitle: "When a viewed or saved product drops in price."
                    )
                    Divider().padding(.leading, 4)
                    NotificationTypeToggle(
                        type: .newProduct,
                        title: "New products from creators",
                        subtitle: "When sellers you follow (or bought from) add listings."
                    )
                    Divider().padding(.leading, 4)
                    NotificationTypeToggle(
                        type: .orderStatusUpdate,
                        title: "Order & shipping updates",
                        subtitle: "Production, shipped, and delivered updates for your purchases."
                    )
                    Divider().padding(.leading, 4)
                    NotificationTypeToggle(
                        type: .orderSupportUpdate,
                        title: "Request & seller updates",
                        subtitle: "Cancel/refund decisions and messages from sellers on your orders."
                    )
                }
            }
            .padding(14)
            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private var deliveryBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How alerts are delivered")
                .font(.tbHeadline)
                .foregroundStyle(TBTheme.icyBlue)

            VStack(alignment: .leading, spacing: 14) {
                deliveryRow(
                    icon: "bell.badge.fill",
                    title: "Outside the app",
                    message: "Push alerts appear on your device when notifications are allowed in system settings."
                )
                deliveryRow(
                    icon: "list.bullet.rectangle.portrait",
                    title: "Inside the app",
                    message: "Notifications refresh when you reopen TenBelow."
                )
                deliveryRow(
                    icon: "slider.horizontal.3",
                    title: "Your control",
                    message: "These switches control which alerts you receive."
                )
            }
            .padding(14)
            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func actionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.tbCaption)
                .foregroundStyle(TBTheme.deepSky)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(TBTheme.skyLight.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func deliveryRow(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TBTheme.deepSky)
                .frame(width: 22, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.tbBodyStrong)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var roleNotificationTypes: [NotificationType] {
        if userRole == "seller" {
            return [.orderReceived, .orderSupportUpdate, .itemFavorited, .system]
        } else {
            return [.priceDrop, .newProduct, .orderStatusUpdate, .orderSupportUpdate]
        }
    }

    @MainActor
    private var enabledTypeCount: Int {
        roleNotificationTypes.filter(NotificationPreferences.isTypeEnabled).count
    }

    @MainActor
    private func setAllTypesEnabled(_ enabled: Bool) {
        for type in roleNotificationTypes {
            UserDefaults.standard.set(enabled, forKey: NotificationPreferences.appStorageKey(for: type))
        }
    }

    private func refreshExternalAlertStatus() async {
        #if os(iOS)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let message: String
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            message = "iPhone alerts are enabled. Make sure Settings → Notifications → TenBelow has Banners, Sounds, and Lock Screen turned on."
        case .denied:
            message = "iPhone alerts are blocked. Open Settings → Notifications → TenBelow and turn on Allow Notifications."
        case .notDetermined:
            message = "Tap Enable iPhone alerts to let TenBelow ask for notification permission."
        @unknown default:
            message = "Notification permission status is unknown."
        }
        await MainActor.run {
            externalAlertStatus = message
        }
        #else
        await MainActor.run {
            externalAlertStatus = "iPhone alerts are available on iOS devices."
        }
        #endif
    }

    private func enableExternalAlerts() async {
        await MainActor.run {
            isEnablingExternalAlerts = true
            externalAlertStatus = "Requesting iPhone notification permission..."
        }

        #if os(iOS)
        await AppDelegate.ensureNotificationsAuthorizedIfNeeded()
        await PushDeviceRegistration.syncAfterIdentityChange()
        await refreshExternalAlertStatus()
        #else
        await MainActor.run {
            externalAlertStatus = "iPhone alerts are available on iOS devices."
        }
        #endif

        await MainActor.run {
            isEnablingExternalAlerts = false
        }
    }

    private func sendTestAlert() async {
        await MainActor.run {
            isEnablingExternalAlerts = true
            externalAlertStatus = "Sending a test alert to this iPhone..."
        }

        #if os(iOS)
        await AppDelegate.ensureNotificationsAuthorizedIfNeeded()
        await PushDeviceRegistration.syncAfterIdentityChange()

        do {
            guard let url = AppConstants.backendBaseURL?.appendingPathComponent("push/test") else {
                await MainActor.run {
                    externalAlertStatus = "Backend URL is not configured, so TenBelow cannot send a test alert yet."
                    isEnablingExternalAlerts = false
                }
                return
            }

            await MarketplaceAuthSession.syncAfterIdentityChange()
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            AppConstants.applyAppClientAuth(to: &request)
            MarketplaceAuthSession.applyAuthenticatedUserAuth(to: &request)

            let (_, response) = try await URLSession.tenBelow.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                await MainActor.run {
                    externalAlertStatus = "TenBelow could not send the test alert yet. Make sure you are signed in and the backend APNs variables are set."
                    isEnablingExternalAlerts = false
                }
                return
            }

            await MainActor.run {
                externalAlertStatus = "Test alert sent. If your phone is unlocked, it may appear as a banner; if locked, check the Lock Screen."
            }
        } catch {
            await MainActor.run {
                externalAlertStatus = "Test alert failed: \(error.localizedDescription)"
            }
        }
        #else
        await MainActor.run {
            externalAlertStatus = "Test alerts are available on iPhone."
        }
        #endif

        await MainActor.run {
            isEnablingExternalAlerts = false
        }
    }
}

// MARK: - Per-type toggle (UserDefaults-backed, matches NotificationStore filtering)

private struct NotificationTypeToggle: View {
    let type: NotificationType
    let title: String
    let subtitle: String

    @AppStorage private var isOn: Bool

    init(type: NotificationType, title: String, subtitle: String) {
        self.type = type
        self.title = title
        self.subtitle = subtitle
        _isOn = AppStorage(wrappedValue: true, NotificationPreferences.appStorageKey(for: type))
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.tbBodyStrong)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        }
        .tint(TBTheme.accent)
    }
}
