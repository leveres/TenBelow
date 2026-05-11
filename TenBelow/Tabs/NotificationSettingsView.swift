//
//  NotificationSettingsView.swift
//

import SwiftUI

struct NotificationSettingsView: View {
    @AppStorage("userRole") private var userRole = "buyer"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                notificationSettingsSection
                deliveryBehaviorSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .background(TBTheme.cloudWhite.ignoresSafeArea())
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
            return [.orderReceived, .itemFavorited, .system]
        } else {
            return [.priceDrop, .newProduct, .orderStatusUpdate]
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
