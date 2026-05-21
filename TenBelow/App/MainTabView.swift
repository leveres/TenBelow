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
        }
        .animation(.easeInOut(duration: 0.5), value: shouldDisplayLoadingOverlay)
        .task {
            guard !hasPerformedInitialRefresh else { return }
            hasPerformedInitialRefresh = true
            await refreshCatalog(force: true)
            hasCompletedInitialLoad = true
        }
        .onAppear {
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

