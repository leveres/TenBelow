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
    @AppStorage("userRole") private var userRole = ""
    @AppStorage("shouldShowHomeEntrySplash") private var shouldShowHomeEntrySplash = false
    @AppStorage("pendingLaunchTab") private var pendingLaunchTab = 0
    @AppStorage("catalogRefreshToken") private var catalogRefreshToken = 0
    var showsLoadingOverlay: Bool = true
    @State private var isShowingEntrySplash = false
    @State private var hasMetMinimumEntrySplashTime = false
    @State private var selectedTab: MainTab = .home
    @State private var lastCatalogRefresh = Date.distantPast

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
        .task { await refreshCatalog(force: true) }
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

            OrdersView()
                .tag(MainTab.orders)
                .tabItem { Label("Orders", systemImage: "shippingbox") }

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

    private var shouldDisplayLoadingOverlay: Bool {
        if isEntrySplashActive {
            return true
        }

        return showsLoadingOverlay && catalog.isLoading
    }

    private func refreshCatalog(force: Bool = false) async {
        let now = Date()
        let shouldRefresh = force || now.timeIntervalSince(lastCatalogRefresh) >= 45
        guard shouldRefresh else { return }
        lastCatalogRefresh = now
        await catalog.load()
    }

    private func dismissEntrySplashIfReady() {
        guard isShowingEntrySplash, hasMetMinimumEntrySplashTime, !catalog.isLoading else { return }

        withAnimation(.easeInOut(duration: 0.26)) {
            isShowingEntrySplash = false
        }

        if let launchTab = MainTab(rawValue: pendingLaunchTab) {
            selectedTab = launchTab
        } else {
            selectedTab = .home
        }

        pendingLaunchTab = MainTab.home.rawValue
    }
}

#Preview {
    MainTabView()
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
        .environmentObject(SellerSubscriptionStore.previewActive)
}
