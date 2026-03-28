//
//  SellOnTenBelowGatewayView.swift
//  TenBelow
//

import SwiftUI

/// Gateway view: routes to Seller Dashboard if registered seller, else to landing page.
struct SellOnTenBelowGatewayView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @AppStorage("sellerAccountCreated") private var accountCreated = false
    @AppStorage("sellerSellerId") private var sellerId = ""
    @AppStorage("sellerBusinessName") private var businessName = ""

    private var isSeller: Bool { accountCreated && !sellerId.isEmpty }

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var resolvedSeller: SellerProfile {
        resolvedSellerProfile(
            sellerId: sellerId,
            storefrontProducts: storefrontProducts,
            remoteProfiles: catalog.sellerProfiles
        ) ?? .previewProfile(sellerId: sellerId, businessName: businessName)
    }

    private var sellerProducts: [Product] {
        storefrontProducts.filter { $0.sellerId == sellerId }
    }

    var body: some View {
        if isSeller {
            SellerDashboardView(
                seller: resolvedSeller,
                products: sellerProducts
            )
        } else {
            SellOnTenBelowLandingView()
        }
    }
}
