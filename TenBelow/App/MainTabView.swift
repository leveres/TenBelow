//
//  MainTabView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/17/26.
//

import SwiftUI
import Combine

private enum MainTab: Int, Hashable {
    case home = 0
    case store = 1
    case drop = 2
    case orders = 3
    case settings = 4
}

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var notifications: NotificationStore
    @EnvironmentObject private var orderStore: OrderStore
    @AppStorage("userRole") private var userRole = ""
    @AppStorage("sellerSellerId") private var sellerSellerId = ""
    @AppStorage("shouldShowHomeEntrySplash") private var shouldShowHomeEntrySplash = false
    @AppStorage("pendingLaunchTab") private var pendingLaunchTab = 0
    @AppStorage("catalogRefreshToken") private var catalogRefreshToken = 0
    var showsLoadingOverlay: Bool = true
    @State private var isShowingEntrySplash = false
    @State private var hasMetMinimumEntrySplashTime = false
    @State private var selectedTab: MainTab = .home
    @State private var lastCatalogRefresh = Date.distantPast
    @State private var lastSellerOrdersRefresh = Date.distantPast
    @State private var hasPerformedInitialRefresh = false
    @State private var hasCompletedInitialLoad = false
    @State private var catalogRefreshJitter = Double.random(in: 0...6)
    @State private var activeNotificationBanner: AppNotification?
    @State private var lastPresentedNotificationID: String?
    @State private var notificationBannerDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            tabContent
                .opacity(shouldDisplayLoadingOverlay ? 0.0 : 1.0)
                .allowsHitTesting(!shouldDisplayLoadingOverlay)
                .animation(.easeInOut(duration: 0.5), value: shouldDisplayLoadingOverlay)

            if shouldDisplayLoadingOverlay {
                AppLoadingOverlay(
                    title: "Loading TenBelow",
                    subtitle: "Pulling in the latest products and pricing."
                )
                .transition(.opacity)
                .zIndex(1)
            }

            if let activeNotificationBanner {
                VStack {
                    InAppNotificationBanner(
                        notification: activeNotificationBanner,
                        audienceLabel: notificationAudienceLabel,
                        dismissAction: dismissNotificationBanner
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .onTapGesture {
                        openNotificationBanner(activeNotificationBanner)
                    }

                    Spacer(minLength: 0)
                }
                .transition(notificationBannerTransition)
                .zIndex(2)
                .accessibilitySortPriority(1)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: shouldDisplayLoadingOverlay)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: activeNotificationBanner?.id)
        .task {
            guard !hasPerformedInitialRefresh else { return }
            hasPerformedInitialRefresh = true
            await refreshCatalog(force: true)
            hasCompletedInitialLoad = true
        }
        .onAppear {
            lastPresentedNotificationID = notifications.currentNotifications.first?.id
            if shouldShowHomeEntrySplash {
                shouldShowHomeEntrySplash = false
                isShowingEntrySplash = true
                hasMetMinimumEntrySplashTime = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) {
                    hasMetMinimumEntrySplashTime = true
                    dismissEntrySplashIfReady()
                }
            }
        }
        .onChange(of: catalog.isLoading) { _, _ in
            dismissEntrySplashIfReady()
        }
        .onChange(of: pendingLaunchTab) { _, newValue in
            guard let launchTab = MainTab(rawValue: newValue), !isEntrySplashActive else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                selectedTab = launchTab
            }
        }
        .onChange(of: catalogRefreshToken) { _, _ in
            Task { await refreshCatalog(force: true) }
        }
        .onChange(of: notifications.currentNotifications.first?.id) { _, newValue in
            presentNotificationBannerIfNeeded(newNotificationID: newValue)
        }
        .onChange(of: "\(userRole)|\(sellerSellerId)") { _, _ in
            lastPresentedNotificationID = notifications.currentNotifications.first?.id
            dismissNotificationBanner()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshCatalog() }
            Task { await refreshSellerOrdersForTabBadgeIfNeeded() }
            if userRole == "seller" {
                Task { await MarketplaceAuthSession.syncAfterIdentityChange() }
            }
        }
        .task(id: "\(userRole)|\(sellerSellerId)") {
            await refreshSellerOrdersForTabBadgeIfNeeded()
        }
    }

    private var isEntrySplashActive: Bool {
        shouldShowHomeEntrySplash || isShowingEntrySplash
    }

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tag(MainTab.home)
                .tabItem { Label("Home", systemImage: "house") }

            Group {
                if userRole == "seller" {
                    NavigationStack {
                        SellOnTenBelowGatewayView()
                    }
                } else {
                    ShopView()
                }
            }
            .tag(MainTab.store)
            .tabItem {
                if userRole == "seller" {
                    Label("Store", systemImage: "storefront")
                } else {
                    Label("Shop", systemImage: "square.grid.2x2")
                }
            }

            DropView()
                .tag(MainTab.drop)
                .tabItem { Label("Drop", systemImage: "flame") }

            NavigationStack {
                OrdersView()
            }
                .tag(MainTab.orders)
                .tabItem { Label("Orders", systemImage: "shippingbox") }
                .badge(ordersTabBadge)

            SettingsView()
                .tag(MainTab.settings)
                .tabItem { Label("Settings", systemImage: "gear") }
                .badge(settingsTabBadge)
        }
        .tint(TBTheme.icyBlue)
    }

    private var notificationAudienceLabel: String {
        userRole == "seller" ? "Seller alert" : "Buyer update"
    }

    private var notificationBannerTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .move(edge: .top).combined(with: .opacity)
    }

    private func presentNotificationBannerIfNeeded(newNotificationID: String?) {
        guard let newNotificationID else { return }
        guard newNotificationID != lastPresentedNotificationID else { return }
        lastPresentedNotificationID = newNotificationID

        guard let notification = notifications.currentNotifications.first(where: { $0.id == newNotificationID }) else {
            return
        }

        activeNotificationBanner = notification
        notificationBannerDismissTask?.cancel()
        notificationBannerDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            await MainActor.run {
                guard activeNotificationBanner?.id == notification.id else { return }
                dismissNotificationBanner()
            }
        }
    }

    private func dismissNotificationBanner() {
        notificationBannerDismissTask?.cancel()
        notificationBannerDismissTask = nil
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            activeNotificationBanner = nil
        }
    }

    private func openNotificationBanner(_ notification: AppNotification) {
        notifications.markAsRead(notification.id)

        if notification.relatedOrderId != nil || notification.relatedExchangeRequestId != nil {
            selectedTab = .orders
        } else if notification.relatedProductId != nil {
            selectedTab = .store
        } else {
            selectedTab = .home
        }

        dismissNotificationBanner()
    }

    private var settingsTabBadge: String? {
        let unread = notifications.unreadCount()
        guard unread > 0 else { return nil }
        return "\(min(unread, 99))"
    }

    /// Seller-only: orders that still need fulfillment steps (start production, ship, or mark delivered).
    private var ordersTabBadge: String? {
        guard userRole == "seller" else { return nil }
        let count = sellerOrdersNeedingAttentionCount
        guard count > 0 else { return nil }
        return "\(min(count, 99))"
    }

    private var sellerOrdersNeedingAttentionCount: Int {
        let sid = sellerSellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else { return 0 }

        return orderStore.orders.filter { order in
            order.shipments.contains { shipment in
                guard shipment.sellerId == sid else { return false }
                return orderStore.nextAction(for: shipment, order: order) != nil
            }
        }.count
    }

    @MainActor
    private func refreshSellerOrdersForTabBadgeIfNeeded() async {
        guard userRole == "seller" else { return }
        let sid = sellerSellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSellerOrdersRefresh) >= 45 else { return }
        lastSellerOrdersRefresh = now
        await orderStore.refreshSellerOrders(sellerId: sid)
    }

    private var shouldDisplayLoadingOverlay: Bool {
        if isEntrySplashActive {
            return true
        }

        return showsLoadingOverlay && !hasCompletedInitialLoad && catalog.isLoading
    }

    private func refreshCatalog(force: Bool = false) async {
        let now = Date()
        let threshold = 45 + catalogRefreshJitter
        let shouldRefresh = force || now.timeIntervalSince(lastCatalogRefresh) >= threshold
        guard shouldRefresh else { return }
        lastCatalogRefresh = now
        if !force {
            catalogRefreshJitter = Double.random(in: 0...6)
        }
        await catalog.load()
    }

    private func dismissEntrySplashIfReady() {
        guard isShowingEntrySplash, hasMetMinimumEntrySplashTime else { return }

        let launchTab = MainTab(rawValue: pendingLaunchTab) ?? .home

        withAnimation(.easeInOut(duration: 0.26)) {
            isShowingEntrySplash = false
            selectedTab = launchTab
        }

        pendingLaunchTab = MainTab.home.rawValue
    }
}

private struct InAppNotificationBanner: View {
    let notification: AppNotification
    let audienceLabel: String
    let dismissAction: () -> Void

    private var style: BannerStyle {
        BannerStyle(notificationType: notification.type)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(style.tint.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: style.iconName)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(style.tint)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(audienceLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .textCase(.uppercase)
                        .foregroundStyle(style.tint)

                    Text(style.typeLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(notification.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(notification.message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: dismissAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.64), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.72),
                                    style.tint.opacity(0.13),
                                    TBTheme.skyLight.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.88),
                            style.tint.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: style.tint.opacity(0.16), radius: 22, y: 10)
        .shadow(color: .white.opacity(0.28), radius: 4, y: -1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(audienceLabel). \(notification.title). \(notification.message)")
        .accessibilityHint("Tap to open the related area.")
    }
}

private struct BannerStyle {
    let iconName: String
    let typeLabel: String
    let tint: Color

    init(notificationType: NotificationType) {
        switch notificationType {
        case .priceDrop:
            iconName = "tag.fill"
            typeLabel = "Price drop"
            tint = Color(red: 0.96, green: 0.36, blue: 0.22)
        case .newProduct:
            iconName = "sparkles"
            typeLabel = "New drop"
            tint = TBTheme.icyBlue
        case .orderReceived:
            iconName = "shippingbox.fill"
            typeLabel = "New order"
            tint = Color(red: 0.22, green: 0.62, blue: 0.36)
        case .orderStatusUpdate:
            iconName = "truck.box.fill"
            typeLabel = "Order update"
            tint = TBTheme.deepSky
        case .exchangeUpdate:
            iconName = "arrow.triangle.2.circlepath"
            typeLabel = "Exchange"
            tint = Color(red: 0.56, green: 0.39, blue: 0.88)
        case .itemFavorited:
            iconName = "heart.fill"
            typeLabel = "Product love"
            tint = Color(red: 0.94, green: 0.25, blue: 0.47)
        case .system:
            iconName = "exclamationmark.circle.fill"
            typeLabel = "Action needed"
            tint = Color(red: 0.96, green: 0.58, blue: 0.18)
        }
    }
}

