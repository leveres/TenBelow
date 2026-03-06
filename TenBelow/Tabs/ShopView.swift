//
//  ShopView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import Combine

struct ShopView: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalog: CatalogStore
    @State private var showCart = false
    @State private var selectedCategory: TBCategory = tbCategories[0] // All

    private var filteredProducts: [Product] {
        MockData.products.filter { product in
            if selectedCategory.title == "All" { return true }
            return product.category.rawValue == selectedCategory.title
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Image("ShopTitle")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 38)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)

                    Text("Everything is $10 & under.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    CategoryFilterBar(
                        categories: tbCategories,
                        selected: $selectedCategory
                    )

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TBTheme.spacingMD) {
                        ForEach(filteredProducts) { product in
                            ProductCard(
                                product: product,
                                seller: .mockLookup(id: product.sellerId),
                                allProducts: MockData.products
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 0)
            .background(TBTheme.cloudWhite)
            .navigationTitle("")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CartButton(itemCount: cart.items.reduce(0) { $0 + $1.quantity }) {
                        showCart = true
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    CartButton(itemCount: cart.items.reduce(0) { $0 + $1.quantity }) {
                        showCart = true
                    }
                }
            }
            #endif
            .sheet(isPresented: $showCart) {
                CartView()
                    .environmentObject(cart)
                    .environmentObject(catalog)
            }
        }
    }
}

#Preview {
    ShopView()
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
}
