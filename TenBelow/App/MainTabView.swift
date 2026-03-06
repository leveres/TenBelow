//
//  MainTabView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/17/26.
//

import SwiftUI
import Combine

struct MainTabView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @AppStorage("userRole") private var userRole = ""

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            Group {
                if userRole == "seller" {
                    SellerDashboardView(
                        seller: .sample,
                        products: MockData.products
                    )
                } else {
                    ShopView()
                }
            }
            .tabItem {
                if userRole == "seller" {
                    Label("Store", systemImage: "storefront")
                } else {
                    Label("Shop", systemImage: "square.grid.2x2")
                }
            }

            DropView()
                .tabItem { Label("Drop", systemImage: "flame") }

            OrdersView()
                .tabItem { Label("Orders", systemImage: "shippingbox") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .tint(TBTheme.icyBlue)
        .task { await catalog.load() }
    }
}

#Preview {
    MainTabView()
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
}
