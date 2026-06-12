//
//  TenBelowApp.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/8/26.
//

import SwiftUI
import Combine
import Stripe

@main
struct TenBelowApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    @StateObject private var cart = CartStore()
    @StateObject private var catalog: CatalogStore
    @StateObject private var commerceEvents: CommerceEventStore
    @StateObject private var buyerEngagement: BuyerEngagementStore
    @StateObject private var localProducts: LocalProductStore
    @StateObject private var orderStore: OrderStore
    @StateObject private var exchangeStore: ExchangeStore
    @StateObject private var notifications: NotificationStore
    @StateObject private var sellerSubscription = SellerSubscriptionStore()
    @StateObject private var sellerInquiries = SellerInquiryStore()

    init() {
        #if DEBUG
        AppConstants.applyLaunchArgumentsForTesting()
        #endif

        let eventStore = CommerceEventStore()
        let engagementStore = BuyerEngagementStore(eventStore: eventStore)
        let productStore = LocalProductStore(eventStore: eventStore)
        let ordersStore = OrderStore(eventStore: eventStore)
        _catalog = StateObject(wrappedValue: CatalogStore(eventStore: eventStore))
        _commerceEvents = StateObject(wrappedValue: eventStore)
        _buyerEngagement = StateObject(wrappedValue: engagementStore)
        _localProducts = StateObject(wrappedValue: productStore)
        _orderStore = StateObject(wrappedValue: ordersStore)
        _exchangeStore = StateObject(wrappedValue: ExchangeStore(eventStore: eventStore, orderStore: ordersStore))
        _notifications = StateObject(
            wrappedValue: NotificationStore(
                eventStore: eventStore,
                buyerEngagement: engagementStore,
                localProducts: productStore,
                orderStore: ordersStore
            )
        )

        if AppConstants.isStripeConfigured {
            StripeAPI.defaultPublishableKey = AppConstants.stripePublishableKey
        }
        #if os(iOS)
        let selectedTabColor = UIColor(red: 42 / 255, green: 109 / 255, blue: 181 / 255, alpha: 1.0)
        let unselectedTabColor = UIColor(red: 155 / 255, green: 181 / 255, blue: 204 / 255, alpha: 1.0)
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        func applyTabColors(_ appearance: UITabBarItemAppearance) {
            appearance.selected.iconColor = selectedTabColor
            appearance.selected.titleTextAttributes = [.foregroundColor: selectedTabColor]
            appearance.normal.iconColor = unselectedTabColor
            appearance.normal.titleTextAttributes = [.foregroundColor: unselectedTabColor]
        }
        applyTabColors(tabBarAppearance.stackedLayoutAppearance)
        applyTabColors(tabBarAppearance.inlineLayoutAppearance)
        applyTabColors(tabBarAppearance.compactInlineLayoutAppearance)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        UITabBar.appearance().tintColor = selectedTabColor
        UITabBar.appearance().unselectedItemTintColor = unselectedTabColor

        // Frost-themed navigation bar titles
        let frostColor = UIColor(red: 0.30, green: 0.52, blue: 0.90, alpha: 1.0)
        let largeTitleAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: frostColor,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold).rounded
        ]
        let inlineTitleAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: frostColor,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold).rounded
        ]
        UINavigationBar.appearance().largeTitleTextAttributes = largeTitleAttrs
        UINavigationBar.appearance().titleTextAttributes = inlineTitleAttrs
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(cart)
                .environmentObject(catalog)
                .environmentObject(commerceEvents)
                .environmentObject(buyerEngagement)
                .environmentObject(localProducts)
                .environmentObject(orderStore)
                .environmentObject(exchangeStore)
                .environmentObject(notifications)
                .environmentObject(sellerSubscription)
                .environmentObject(sellerInquiries)
                .accentColor(TBTheme.icyBlue)
        }
    }
}
