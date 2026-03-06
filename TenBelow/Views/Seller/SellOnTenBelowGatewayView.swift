//
//  SellOnTenBelowGatewayView.swift
//  TenBelow
//

import SwiftUI

/// Gateway view: routes to Seller Dashboard if registered seller, else to landing page.
struct SellOnTenBelowGatewayView: View {
    @AppStorage("sellerAccountCreated") private var accountCreated = false
    @AppStorage("sellerSellerId") private var sellerId = ""

    private var isSeller: Bool { accountCreated && !sellerId.isEmpty }

    var body: some View {
        if isSeller {
            SellerDashboardView(
                seller: .sample,
                products: MockData.products
            )
        } else {
            SellOnTenBelowLandingView()
        }
    }
}
