//
//  NotificationActivityView.swift
//

import SwiftUI

private enum NotificationDestination: Identifiable, Hashable {
    case product(Product)
    case order(String)

    var id: String {
        switch self {
        case .product(let product):
            return "product:\(product.id)"
        case .order(let orderId):
            return "order:\(orderId)"
        }
    }
}

/// In-app activity history for the current account, combining favorites and notifications.
struct NotificationActivityView: View {
    @EnvironmentObject private var notificationStore: NotificationStore
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @EnvironmentObject private var orderStore: OrderStore
    @AppStorage("userRole") private var userRole = "buyer"
    @AppStorage("sellerSellerId") private var sellerId = ""

    @State private var selectedDestination: NotificationDestination?

    private var notifications: [AppNotification] {
        notificationStore.currentNotifications.filter { NotificationPreferences.isTypeEnabled($0.type) }
    }

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var favoriteProducts: [Product] {
        let favoritesByID = Set(buyerEngagement.favoriteProductIDs)
        return storefrontProducts
            .filter { favoritesByID.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var showsBuyerFavoritesSection: Bool {
        userRole != "seller"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsBuyerFavoritesSection {
                    favoritesSection
                }

                activitySectionHeader

                if notifications.isEmpty, !(showsBuyerFavoritesSection && !favoriteProducts.isEmpty) {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "tray",
                        description: Text(emptyActivityDescription)
                    )
                    .padding(.top, 28)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(notifications) { notification in
                            notificationRow(notification)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .background(TBTheme.cloudWhite.ignoresSafeArea())
        .navigationDestination(item: $selectedDestination) { destination in
            switch destination {
            case .product(let product):
                ProductDetailView(product: product)
            case .order(let orderId):
                OrderDetailView(
                    orderId: orderId,
                    mode: userRole == "seller" ? .seller : .buyer,
                    currentSellerId: userRole == "seller" ? activeSellerId : nil
                )
            }
        }
    }

    private var emptyActivityDescription: String {
        userRole == "seller"
            ? "Orders, favorites, and reminders appear here."
            : "Favorites, price drops, new listings, and order updates appear here."
    }

    private var activeSellerId: String {
        let trimmed = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "SELL-01" : trimmed
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Favorites")
                .font(.tbHeadline)
                .foregroundStyle(TBTheme.icyBlue)

            Text("Saved items stay here for quick access alongside your notifications.")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if favoriteProducts.isEmpty {
                Text("Tap the heart on products you like while shopping. Your saved items will show up here.")
                    .font(.tbBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
                    )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(favoriteProducts) { product in
                            Button {
                                selectedDestination = .product(product)
                            } label: {
                                NotificationFavoriteTile(product: product)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var activitySectionHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent activity")
                .font(.tbHeadline)
                .foregroundStyle(TBTheme.icyBlue)

            Text("Tap an item for details. Change notification types in Settings → Notification settings.")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func notificationRow(_ notification: AppNotification) -> some View {
        Button {
            open(notification)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(TBTheme.skyLight.opacity(0.62))
                        .frame(width: 40, height: 40)

                    Image(systemName: icon(for: notification.type))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TBTheme.deepSky)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(notification.title)
                            .font(.tbBodyStrong)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 6)

                        if !notification.isRead {
                            Circle()
                                .fill(TBTheme.accent)
                                .frame(width: 9, height: 9)
                                .padding(.top, 4)
                        }
                    }

                    Text(notification.message)
                        .font(.tbBody)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(relativeTimestamp(for: notification.createdAt))
                        .font(.tbCaption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(notification.isRead ? TBTheme.skyBlue.opacity(0.10) : TBTheme.accent.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notificationAccessibilityLabel(notification))
        .accessibilityHint("Opens this notification.")
    }

    private func open(_ notification: AppNotification) {
        notificationStore.markAsRead(notification.id)

        if let orderId = notification.relatedOrderId,
           orderStore.order(withId: orderId) != nil {
            selectedDestination = .order(orderId)
            return
        }

        if let productId = notification.relatedProductId,
           let product = localProducts.product(withId: productId) {
            selectedDestination = .product(product)
            return
        }
    }

    private func icon(for type: NotificationType) -> String {
        switch type {
        case .priceDrop:
            return "tag.fill"
        case .newProduct:
            return "shippingbox.fill"
        case .orderReceived:
            return "cart.fill.badge.plus"
        case .orderStatusUpdate:
            return "truck.box.fill"
        case .itemFavorited:
            return "heart.fill"
        case .system:
            return "exclamationmark.bubble.fill"
        }
    }

    private func relativeTimestamp(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func notificationAccessibilityLabel(_ notification: AppNotification) -> String {
        let readState = notification.isRead ? "Read" : "Unread"
        return "\(readState). \(notification.title). \(notification.message). \(relativeTimestamp(for: notification.createdAt))."
    }
}

private struct NotificationFavoriteTile: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StorefrontImageView(reference: product.primaryImageReference) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TBTheme.skyLight.opacity(0.30))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1)
            )

            Text(product.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 100, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(Money.format(cents: product.priceCents))
                .font(.tbMicro)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(product.name), \(Money.format(cents: product.priceCents)), \(product.category.rawValue)")
        .accessibilityHint("Opens favorited product.")
    }
}
