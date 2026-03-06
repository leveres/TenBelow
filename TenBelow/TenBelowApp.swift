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
    @StateObject private var cart = CartStore()
    @StateObject private var catalog = CatalogStore()

    init() {
        StripeAPI.defaultPublishableKey = AppConstants.stripePublishableKey
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
                .accentColor(TBTheme.icyBlue)
        }
    }
}
