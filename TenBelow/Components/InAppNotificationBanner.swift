//
//  InAppNotificationBanner.swift
//  TenBelow
//
//  Compact in-app banner shared by buyers and sellers, sized and animated to read like a
//  native iOS notification rather than a modal card.
//
//  Classification here is presentation-only: it reads an existing notification and never
//  changes which events are recorded or delivered.
//

import SwiftUI

struct NotificationBannerContext {
    var orderLabel: String?
    var productImageReference: String?
}

enum NotificationBannerKind {
    case informational
    case success
    case actionRequired
    case commerce
    case message
}

enum NotificationBannerAccent {
    case brand
    case success
    case warning
    case critical

    var color: Color {
        switch self {
        case .brand:
            return TBTheme.deepSky
        case .success:
            return Color(red: 0.18, green: 0.62, blue: 0.38)
        case .warning:
            return Color(red: 0.85, green: 0.52, blue: 0.12)
        case .critical:
            return Color(red: 0.82, green: 0.24, blue: 0.22)
        }
    }
}

struct NotificationBannerPresentation {
    let kind: NotificationBannerKind
    let iconName: String
    let accent: NotificationBannerAccent
    let prefersProductThumbnail: Bool

    var isActionRequired: Bool {
        kind == .actionRequired
    }

    /// Informational banners read in about four and a half seconds. Action-required banners get
    /// a little longer, but still expire so one alert can never hold the queue.
    static let standardDismissNanoseconds: UInt64 = 4_500_000_000
    static let actionRequiredDismissNanoseconds: UInt64 = 7_500_000_000

    static func dismissDelay(for notification: AppNotification) -> UInt64 {
        resolve(notification).isActionRequired ? actionRequiredDismissNanoseconds : standardDismissNanoseconds
    }

    static func resolve(_ notification: AppNotification) -> NotificationBannerPresentation {
        let title = notification.title.lowercased()

        if notification.type == .priceDrop || title.contains("price drop") {
            return NotificationBannerPresentation(
                kind: .commerce,
                iconName: "tag.fill",
                accent: .brand,
                prefersProductThumbnail: true
            )
        }

        if notification.type == .newProduct || title.contains("new drop") {
            return NotificationBannerPresentation(
                kind: .commerce,
                iconName: "sparkles",
                accent: .brand,
                prefersProductThumbnail: true
            )
        }

        if notification.type == .itemFavorited {
            return NotificationBannerPresentation(
                kind: .commerce,
                iconName: "heart.fill",
                accent: .brand,
                prefersProductThumbnail: true
            )
        }

        if notification.type == .system
            || title.contains("action needed")
            || title.contains("more info")
            || title.contains("new buyer request") {
            return NotificationBannerPresentation(
                kind: .actionRequired,
                iconName: "exclamationmark.triangle.fill",
                accent: .warning,
                prefersProductThumbnail: false
            )
        }

        if title.contains("message") || title.contains("replied") {
            return NotificationBannerPresentation(
                kind: .message,
                iconName: "message.fill",
                accent: .brand,
                prefersProductThumbnail: false
            )
        }

        if title.contains("refund") && (title.contains("approved") || title.contains("accepted")) {
            return NotificationBannerPresentation(
                kind: .success,
                iconName: "arrow.uturn.backward.circle.fill",
                accent: .success,
                prefersProductThumbnail: false
            )
        }

        if (title.contains("exchange") || title.contains("replacement"))
            && (title.contains("approved") || title.contains("accepted")) {
            return NotificationBannerPresentation(
                kind: .success,
                iconName: "arrow.left.arrow.right",
                accent: .success,
                prefersProductThumbnail: false
            )
        }

        if title.contains("approved") || title.contains("accepted") {
            return NotificationBannerPresentation(
                kind: .success,
                iconName: "checkmark.circle.fill",
                accent: .success,
                prefersProductThumbnail: false
            )
        }

        if title.contains("denied")
            || title.contains("declined")
            || title.contains("cancelled")
            || title.contains("canceled") {
            return NotificationBannerPresentation(
                kind: .informational,
                iconName: "xmark.circle.fill",
                accent: .critical,
                prefersProductThumbnail: false
            )
        }

        if title.contains("shipped") {
            return NotificationBannerPresentation(
                kind: .informational,
                iconName: "truck.box.fill",
                accent: .brand,
                prefersProductThumbnail: notification.relatedProductId != nil
            )
        }

        if title.contains("delivered") {
            return NotificationBannerPresentation(
                kind: .success,
                iconName: "checkmark.circle.fill",
                accent: .success,
                prefersProductThumbnail: notification.relatedProductId != nil
            )
        }

        if title.contains("production") || title.contains("prepared") || title.contains("being made") {
            return NotificationBannerPresentation(
                kind: .informational,
                iconName: "hammer.fill",
                accent: .brand,
                prefersProductThumbnail: notification.relatedProductId != nil
            )
        }

        if title.contains("confirmed") {
            return NotificationBannerPresentation(
                kind: .success,
                iconName: "checkmark.circle.fill",
                accent: .success,
                prefersProductThumbnail: notification.relatedProductId != nil
            )
        }

        if notification.type == .orderReceived || title.contains("new order") {
            return NotificationBannerPresentation(
                kind: .informational,
                iconName: "shippingbox.fill",
                accent: .brand,
                prefersProductThumbnail: notification.relatedProductId != nil
            )
        }

        if notification.type == .exchangeUpdate || title.contains("exchange") || title.contains("replacement") {
            return NotificationBannerPresentation(
                kind: .informational,
                iconName: "arrow.left.arrow.right",
                accent: .brand,
                prefersProductThumbnail: false
            )
        }

        if notification.type == .orderSupportUpdate {
            return NotificationBannerPresentation(
                kind: .message,
                iconName: "message.fill",
                accent: .brand,
                prefersProductThumbnail: false
            )
        }

        return NotificationBannerPresentation(
            kind: .informational,
            iconName: "bell.fill",
            accent: .brand,
            prefersProductThumbnail: notification.relatedProductId != nil
        )
    }
}

struct InAppNotificationBanner: View {
    let notification: AppNotification
    let context: NotificationBannerContext
    let openAction: () -> Void
    let dismissAction: () -> Void
    /// Reports finger-down state so the host can hold the auto-dismiss timer mid-tap.
    var pressChanged: (Bool) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .subheadline) private var iconSide: CGFloat = 34

    private var presentation: NotificationBannerPresentation {
        NotificationBannerPresentation.resolve(notification)
    }

    private var bannerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Button(action: openAction) {
                HStack(alignment: .top, spacing: 10) {
                    leadingMark

                    VStack(alignment: .leading, spacing: 1) {
                        Text(notification.title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(notification.message)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(metadataLine)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(BannerOpenButtonStyle(pressChanged: pressChanged))
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint("Opens the related area.")

            dismissButton
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .padding(.vertical, 9)
        .background {
            // One coherent surface for the whole banner: native Liquid Glass, or an opaque
            // material when Reduce Transparency is on. Never nested per child element.
            if reduceTransparency {
                bannerShape
                    .fill(.background)
                    .overlay {
                        bannerShape.strokeBorder(opaqueBorderColor, lineWidth: 1)
                    }
            } else {
                bannerShape.fill(.clear).glassEffect(.regular, in: bannerShape)
            }
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.10), radius: 12, y: 5)
    }

    private var dismissButton: some View {
        Button(action: dismissAction) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.08), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss notification")
    }

    private var opaqueBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : TBTheme.skyBlue.opacity(0.32)
    }

    private var metadataLine: String {
        let when = relativeTimestamp(for: notification.createdAt)
        guard let orderLabel = context.orderLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !orderLabel.isEmpty
        else {
            return when
        }
        return "\(orderLabel) · \(when)"
    }

    private var accessibilitySummary: String {
        "\(notification.title). \(notification.message). \(metadataLine)"
    }

    @ViewBuilder
    private var leadingMark: some View {
        let reference = context.productImageReference?.trimmingCharacters(in: .whitespacesAndNewlines)
        if presentation.prefersProductThumbnail, let reference, !reference.isEmpty {
            StorefrontImageView(reference: reference, contentMode: .fill) {
                iconBadge
            }
            .frame(width: iconSide, height: iconSide)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
        } else {
            iconBadge
        }
    }

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(presentation.accent.color.opacity(colorScheme == .dark ? 0.24 : 0.14))
            .frame(width: iconSide, height: iconSide)
            .overlay {
                Image(systemName: presentation.iconName)
                    .font(.system(size: max(13, iconSide * 0.44), weight: .semibold))
                    .foregroundStyle(presentation.accent.color)
            }
            .accessibilityHidden(true)
    }

    private func relativeTimestamp(for date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 45 {
            return "now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

/// Plain button style that also reports press state, so a banner is never pulled away
/// while the user is mid-tap.
private struct BannerOpenButtonStyle: ButtonStyle {
    let pressChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onChange(of: configuration.isPressed) { _, isPressed in
                pressChanged(isPressed)
            }
    }
}

extension AnyTransition {
    /// Slight drop-in from above with a fade, and a slight lift on the way out.
    static func tbNotificationBanner(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(y: -18).combined(with: .opacity),
            removal: .offset(y: -12).combined(with: .opacity)
        )
    }
}
