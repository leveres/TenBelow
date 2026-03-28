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
    @StateObject private var catalog = CatalogStore()
    @StateObject private var commerceEvents: CommerceEventStore
    @StateObject private var buyerEngagement: BuyerEngagementStore
    @StateObject private var localProducts: LocalProductStore
    @StateObject private var orderStore: OrderStore
    @StateObject private var notifications: NotificationStore
    @StateObject private var sellerSubscription = SellerSubscriptionStore()
    @StateObject private var buyerSellerThreads = BuyerSellerThreadStore()

    init() {
        let eventStore = CommerceEventStore()
        let engagementStore = BuyerEngagementStore(eventStore: eventStore)
        let productStore = LocalProductStore(eventStore: eventStore)
        let ordersStore = OrderStore(eventStore: eventStore)
        _commerceEvents = StateObject(wrappedValue: eventStore)
        _buyerEngagement = StateObject(wrappedValue: engagementStore)
        _localProducts = StateObject(wrappedValue: productStore)
        _orderStore = StateObject(wrappedValue: ordersStore)
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
        UITabBar.appearance().unselectedItemTintColor = UIColor.systemGray

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
                .environmentObject(notifications)
                .environmentObject(sellerSubscription)
                .environmentObject(buyerSellerThreads)
                .accentColor(TBTheme.icyBlue)
        }
    }
}
