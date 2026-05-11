//
//  NotificationActivityView.swift
//

import SwiftUI

private enum NotificationDestination: Identifiable, Hashable {
    case product(Product)
    case order(String)
    case exchange(String)

    var id: String {
        switch self {
        case .product(let product):
            return "product:\(product.id)"
        case .order(let orderId):
            return "order:\(orderId)"
        case .exchange(let exchangeRequestId):
            return "exchange:\(exchangeRequestId)"
        }
    }
}

/// Buyer hub for saved favorites and in-app notifications (sellers see notifications only).
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
            VStack(alignment: .leading, spacing: 20) {
                if showsBuyerFavoritesSection {
                    favoritesSection
                }

                notificationsSection
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
            case .exchange(let exchangeRequestId):
                ExchangeStatusScreen(exchangeRequestId: exchangeRequestId)
            }
        }
    }

    private var emptyNotificationsDescription: String {
        userRole == "seller"
            ? "Orders and account updates appear here when there’s something new."
            : "Order updates, price drops, and alerts you’ve turned on appear here."
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

            Text("Saved items stay here for quick access.")
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

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notifications")
                .font(.tbHeadline)
                .foregroundStyle(TBTheme.icyBlue)

            Text("Tap a notification for details. Change types in Settings → Notification settings.")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if notifications.isEmpty {
                ContentUnavailableView(
                    "No notifications yet",
                    systemImage: "bell",
                    description: Text(emptyNotificationsDescription)
                )
                .padding(.top, 12)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(notifications) { notification in
                        notificationRow(notification)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func notificationRow(_ notification: AppNotification) -> some View {
        Button {
            open(notification)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                notificationThumbnail(notification)

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
            .padding(10)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(notification.isRead ? TBTheme.skyBlue.opacity(0.10) : TBTheme.accent.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notificationAccessibilityLabel(notification))
        .accessibilityHint("Opens this notification.")
    }

    @ViewBuilder
    private func notificationThumbnail(_ notification: AppNotification) -> some View {
        if let product = productForNotification(notification) {
            StorefrontImageView(reference: product.primaryImageReference, contentMode: .fill) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TBTheme.skyLight.opacity(0.30))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1)
            )
        } else if let seller = sellerForNotification(notification) {
            StorefrontImageView(reference: seller.avatarURL?.absoluteString, contentMode: .fill) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white, Color(red: 0.90, green: 0.95, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Text(sellerAvatarInitials(for: seller))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.24, green: 0.47, blue: 0.78))
                    }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.05), lineWidth: 0.8)
            )
        } else {
            ZStack {
                Circle()
                    .fill(TBTheme.skyLight.opacity(0.62))
                    .frame(width: 36, height: 36)

                Image(systemName: icon(for: notification.type))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky)
            }
        }
    }

    private func open(_ notification: AppNotification) {
        notificationStore.markAsRead(notification.id)

        if let product = productForNotification(notification) {
            selectedDestination = .product(product)
            return
        }

        if let orderId = notification.relatedOrderId,
           orderStore.order(withId: orderId) != nil {
            selectedDestination = .order(orderId)
            return
        }

        if let exchangeRequestId = notification.relatedExchangeRequestId {
            selectedDestination = .exchange(exchangeRequestId)
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
        case .exchangeUpdate:
            return "arrow.triangle.2.circlepath.circle.fill"
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

    private func productForNotification(_ notification: AppNotification) -> Product? {
        guard let productId = notification.relatedProductId else { return nil }
        return storefrontProducts.first(where: { $0.id == productId }) ?? localProducts.product(withId: productId)
    }

    private func sellerForNotification(_ notification: AppNotification) -> SellerProfile? {
        guard let sellerId = notification.relatedSellerId else { return nil }
        return resolvedSellerProfile(
            sellerId: sellerId,
            storefrontProducts: storefrontProducts.filter { $0.sellerId == sellerId },
            remoteProfiles: catalog.sellerProfiles
        )
    }

    private func sellerAvatarInitials(for seller: SellerProfile) -> String {
        let words = seller.displayName.split(whereSeparator: \.isWhitespace)
        let initials = words.prefix(2).compactMap { $0.first }.map(String.init)
        if !initials.isEmpty {
            return initials.joined().uppercased()
        }
        let fallback = seller.handle.replacingOccurrences(of: "@", with: "")
        return String(fallback.prefix(2)).uppercased()
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
