//
//  MainTabView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/17/26.
//

import SwiftUI
import Combine

enum MainTab: Int, Hashable {
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
    @AppStorage(TabLaunchBridge.pendingLaunchTabTokenKey) private var pendingLaunchTabToken = ""
    @AppStorage("catalogRefreshToken") private var catalogRefreshToken = 0
    var showsLoadingOverlay: Bool = true
    @State private var isShowingEntrySplash = false
    @State private var hasMetMinimumEntrySplashTime = false
    @State private var selectedTab: MainTab = .home
    @State private var lastCatalogRefresh = Date.distantPast
    @State private var lastSellerOrdersRefresh = Date.distantPast
    @State private var lastDropStatusRefresh = Date.distantPast
    @State private var hasPerformedInitialRefresh = false
    @State private var hasCompletedInitialLoad = false
    @State private var catalogRefreshJitter = Double.random(in: 0...6)
    @State private var currentDropStatus: CurrentDropResponse?
    @State private var isDropStatusRefreshInFlight = false
    @State private var catalogRefreshDebounceTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            tabContent
                .opacity(shouldDisplayLoadingOverlay ? 0.0 : 1.0)
                .allowsHitTesting(!shouldDisplayLoadingOverlay)
                .animation(reduceMotion ? nil : TBMotion.surface, value: shouldDisplayLoadingOverlay)

            if shouldDisplayLoadingOverlay {
                AppLoadingOverlay(
                    title: "Loading TenBelow",
                    subtitle: "Pulling in the latest products and pricing."
                )
                .transition(.opacity)
                .zIndex(1)
            }

        }
        .task {
            #if DEBUG
            AppConstants.refreshDebugBackendBaseURLOverrideCache()
            #endif
            guard !hasPerformedInitialRefresh else { return }
            hasPerformedInitialRefresh = true
            await refreshCatalog(force: true)
            await refreshDropStatusIfNeeded(force: true)
            hasCompletedInitialLoad = true
        }
        .onAppear {
            #if DEBUG
            AppConstants.refreshDebugBackendBaseURLOverrideCache()
            #endif
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
            applyPendingLaunchTab(newValue)
        }
        .onChange(of: pendingLaunchTabToken) { _, _ in
            applyPendingLaunchTab(pendingLaunchTab)
        }
        .onChange(of: selectedTab) { _, newValue in
            guard newValue == .drop else { return }
            Task { await refreshDropStatusIfNeeded() }
        }
        .onChange(of: catalogRefreshToken) { _, _ in
            catalogRefreshDebounceTask?.cancel()
            catalogRefreshDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await refreshCatalog(force: true)
            }
        }
        .onChange(of: "\(userRole)|\(sellerSellerId)") { _, _ in
            NotificationBannerCenter.shared.resetForIdentityChange()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            #if DEBUG
            AppConstants.refreshDebugBackendBaseURLOverrideCache()
            #endif
            Task { await refreshCatalog() }
            Task { await refreshDropStatusIfNeeded() }
            Task { await refreshSellerOrdersForTabBadgeIfNeeded() }
            Task { await AccountModerationStore.shared.refresh() }
            if userRole == "seller" {
                Task { _ = try? await MarketplaceAuthSession.ensureSellerSessionReady() }
            }
            Task { await PushDeviceRegistration.syncAfterIdentityChange() }
        }
        .task(id: "\(userRole)|\(sellerSellerId)") {
            await refreshSellerOrdersForTabBadgeIfNeeded()
            await PushDeviceRegistration.syncAfterIdentityChange()
        }
        .task(id: "seller-welcome|\(userRole)|\(sellerSellerId)") {
            guard userRole == "seller", !sellerSellerId.isEmpty else { return }
            try? await SellerAPI.completeAppOnboarding()
        }
    }

    private var isEntrySplashActive: Bool {
        shouldShowHomeEntrySplash || isShowingEntrySplash
    }

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .environment(\.tbTabIsActive, selectedTab == .home)
                .tag(MainTab.home)
                .tabItem { Label("Home", systemImage: "house.fill") }

            Group {
                if userRole == "seller" {
                    NavigationStack {
                        SellOnTenBelowGatewayView()
                    }
                } else {
                    ShopView()
                }
            }
            .environment(\.tbTabIsActive, selectedTab == .store)
            .tag(MainTab.store)
            .tabItem {
                if userRole == "seller" {
                    Label("Store", systemImage: "storefront.fill")
                } else {
                    Label("Shop", systemImage: "storefront.fill")
                }
            }

            DropView()
                .environment(\.tbTabIsActive, selectedTab == .drop)
                .tag(MainTab.drop)
                .tabItem { Label("Weekly Drop", systemImage: dropTabSymbolName) }
                .badge(isWeeklyDropLive ? "LIVE" : nil)

            NavigationStack {
                OrdersView()
            }
                .environment(\.tbTabIsActive, selectedTab == .orders)
                .tag(MainTab.orders)
                .tabItem { Label("Orders", systemImage: "shippingbox.fill") }
                .badge(ordersTabBadge)

            SettingsView()
                .environment(\.tbTabIsActive, selectedTab == .settings)
                .tag(MainTab.settings)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .badge(settingsTabBadge)
        }
        .tint(tabBarTint)
    }

    private var isWeeklyDropLive: Bool {
        currentDropStatus?.active == true
    }

    private var dropTabSymbolName: String {
        "arrow.down.circle.fill"
    }

    private var tabBarTint: Color {
        Color(red: 42 / 255, green: 109 / 255, blue: 181 / 255)
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

    private func refreshDropStatusIfNeeded(force: Bool = false) async {
        let now = Date()
        guard !isDropStatusRefreshInFlight else { return }
        guard force || now.timeIntervalSince(lastDropStatusRefresh) >= 45 else { return }
        isDropStatusRefreshInFlight = true
        defer { isDropStatusRefreshInFlight = false }
        lastDropStatusRefresh = now

        do {
            currentDropStatus = try await DropAPI.currentDrop()
        } catch {
            // Keep the previous tab state during transient network failures.
        }
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

    private func applyPendingLaunchTab(_ rawValue: Int) {
        guard let launchTab = MainTab(rawValue: rawValue), !isEntrySplashActive else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedTab = launchTab
        }
    }
}


