//
//  CategoryView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import Combine

struct CategoryView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore

    let category: Category?
    let displayTitle: String
    let displayIcon: String

    init(category: Category) {
        self.category = category
        self.displayTitle = category.rawValue
        self.displayIcon = category.icon
    }

    init(allProducts tbCategory: TBCategory) {
        self.category = nil
        self.displayTitle = tbCategory.title
        self.displayIcon = tbCategory.icon
    }

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var sellerProfilesByID: [String: SellerProfile] {
        resolvedSellerProfilesByID(
            storefrontProducts: storefrontProducts,
            remoteProfiles: catalog.sellerProfiles
        )
    }

    private var products: [Product] {
        guard let category else { return storefrontProducts }
        return storefrontProducts.filter { $0.category == category }
    }

    var body: some View {
        ScrollView {
            if products.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: displayIcon)
                        .font(.system(size: 40))
                        .foregroundStyle(TBTheme.skyBlue)

                    Text("No listings yet")
                        .font(.headline)

                    Text("Nothing is live in \(displayTitle) right now. Open the Shop tab to browse the full storefront, or check back after sellers add new items.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TBTheme.spacingMD) {
                    ForEach(products) { product in
                        ProductCard(
                            product: product,
                            seller: sellerProfilesByID[product.sellerId],
                            allProducts: storefrontProducts
                        )
                    }
                }
                .padding()
            }
        }
        .background(TBTheme.cloudWhite)
        .navigationTitle(displayTitle)
    }
}

