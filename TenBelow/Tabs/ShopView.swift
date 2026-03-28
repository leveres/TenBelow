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
    @EnvironmentObject private var localProducts: LocalProductStore
    @State private var showCart = false
    @State private var selectedCategory: TBCategory = tbCategories[0] // All
    @State private var searchText = ""

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

    private var filteredProducts: [Product] {
        storefrontProducts.filter { product in
            let matchesCategory = selectedCategory.title == "All" || product.category.rawValue == selectedCategory.title
            let matchesSearch = matchesSearchQuery(product)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    // Header — no navigation bar on Shop so this can sit directly under the safe area
                    VStack(alignment: .leading, spacing: 2) {
                        SnowfallTitleContainer(
                            cornerRadius: 26,
                            horizontalPadding: 12,
                            verticalPadding: 6,
                            flakeCount: 78,
                            effectHorizontalInset: 16,
                            effectVerticalInset: 12
                        ) {
                            Image("ShopTitle")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 154)
                                // Asset often has transparent padding under the cloud — tuck subtitle closer.
                                .padding(.bottom, -18)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Everything is $10 and under.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, -6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, -4)
                    .padding(.bottom, 4)
                    .background(TBTheme.cloudWhite)

                    searchField

                    // Filter pills — fixed, scroll horizontally
                    CategoryFilterBar(
                        categories: tbCategories,
                        selected: $selectedCategory
                    )
                    .padding(.top, -2)
                    .padding(.bottom, 4)

                    // Scrollable: product grid only (up and down)
                    if filteredProducts.isEmpty {
                        VStack(spacing: 14) {
                            Spacer()
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 36))
                                .foregroundStyle(TBTheme.skyBlue)
                            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No products to show" : "No matches found")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(TBTheme.deepSky)
                            Text(emptyStateMessage)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TBTheme.spacingMD) {
                                ForEach(filteredProducts) { product in
                                    ProductCard(
                                        product: product,
                                        seller: sellerProfilesByID[product.sellerId],
                                        allProducts: storefrontProducts
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 28)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(TBTheme.cloudWhite)

                CartButton(itemCount: cart.items.reduce(0) { $0 + $1.quantity }) {
                    showCart = true
                }
                .padding(.trailing, 10)
                .safeAreaPadding(.top, 2)
            }
            .background(TBTheme.cloudWhite)
            #if os(iOS) || os(visionOS)
            // Inline bar + empty title still reserve a full row; cart floats high while content sits below.
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showCart) {
                CartView()
                    .environmentObject(cart)
                    .environmentObject(catalog)
                    .environmentObject(localProducts)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TBTheme.deepSky.opacity(0.72))

            TextField("Search products, materials, or sellers", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search products")
                .accessibilityHint("Search by product name, material, seller, or category.")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(TBTheme.cloudWhite)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var emptyStateMessage: String {
        if !normalizedSearchText.isEmpty {
            return "Try a different word, seller, or category."
        }
        return catalog.lastLoadError ?? "Try another category or check back soon."
    }

    private func matchesSearchQuery(_ product: Product) -> Bool {
        guard !normalizedSearchText.isEmpty else { return true }

        let seller = sellerProfilesByID[product.sellerId]
        let searchableParts = [
            product.name,
            product.material,
            product.category.rawValue,
            seller?.displayName ?? "",
            seller?.handle ?? ""
        ]

        return searchableParts
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(normalizedSearchText)
    }
}

#Preview {
    let events = CommerceEventStore()
    ShopView()
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
        .environmentObject(BuyerEngagementStore(eventStore: events))
        .environmentObject(LocalProductStore(eventStore: events))
}
