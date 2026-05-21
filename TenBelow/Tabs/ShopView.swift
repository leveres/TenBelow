//
//  ShopView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import Combine

private enum ShopHighlightFilter: String, CaseIterable, Identifiable {
    /// Full list for current category + search (distinct label from category “All”).
    case everything = "Everything"
    case latest = "Latest"
    case creatorClips = "Creator Clips"
    case priceDrops = "Price Drops"

    var id: String { rawValue }
}

struct ShopView: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @State private var showCart = false
    @State private var selectedCategory: TBCategory = tbCategories[0] // All
    @State private var searchText = ""
    @State private var selectedHighlight: ShopHighlightFilter = .everything
    @State private var cachedShopSnapshot = ShopSnapshot()
    @State private var cachedShopSnapshotVersion: Int?

    private let shopGridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private struct ShopSnapshot {
        var storefrontProducts: [Product] = []
        var sellerProfilesByID: [String: SellerProfile] = [:]
        var displayedProducts: [Product] = []
    }

    private var shopSnapshot: ShopSnapshot {
        if cachedShopSnapshotVersion == shopSnapshotVersion {
            return cachedShopSnapshot
        }
        return computeShopSnapshot()
    }

    private var displayedProducts: [Product] {
        shopSnapshot.displayedProducts
    }

    private var storefrontProducts: [Product] {
        shopSnapshot.storefrontProducts
    }

    private var sellerProfilesByID: [String: SellerProfile] {
        shopSnapshot.sellerProfilesByID
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
                                .padding(.bottom, TopLevelHeaderMetrics.titleArtBottomTuck)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Everything is $10 and under.")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .tracking(-0.2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [TBTheme.deepSky, TBTheme.skyBlue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: .white.opacity(0.45), radius: 1, y: 1)
                            .padding(.top, -6)
                    }
                    .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
                    .padding(.top, TopLevelHeaderMetrics.shopTopInset - 2)
                    .padding(.bottom, TopLevelHeaderMetrics.shopBottomInset - 2)
                    .padding(.horizontal, TopLevelHeaderMetrics.shopOuterHorizontalInset)

                    searchField

                    // Filter pills — fixed, scroll horizontally
                    CategoryFilterBar(
                        categories: tbCategories,
                        selected: $selectedCategory
                    )
                    .padding(.top, TopLevelHeaderMetrics.shopFilterTopInset - 2)
                    .padding(.bottom, TopLevelHeaderMetrics.shopFilterBottomInset - 2)

                    // Scrollable: product grid only (up and down)
                    quickFilterBar

                    if displayedProducts.isEmpty {
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
                        GeometryReader { geometry in
                            ScrollView {
                                LazyVGrid(columns: shopGridColumns, spacing: 10) {
                                    ForEach(displayedProducts) { product in
                                        ProductCard(
                                            product: product,
                                            seller: sellerProfilesByID[product.sellerId],
                                            allProducts: storefrontProducts,
                                            style: .compact
                                        )
                                    }
                                }
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: geometry.size.height,
                                    alignment: .topLeading
                                )
                                .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
                                .padding(.bottom, 28)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(TBTheme.cloudWhite)

                CartButton(itemCount: cart.items.reduce(0) { $0 + $1.quantity }) {
                    showCart = true
                }
                .padding(.trailing, TopLevelChromeMetrics.manualCartTrailingInset)
                .safeAreaPadding(.top, TopLevelChromeMetrics.manualCartTopInset)
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
            .task(id: shopSnapshotVersion) {
                cachedShopSnapshot = computeShopSnapshot()
                cachedShopSnapshotVersion = shopSnapshotVersion
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TBTheme.deepSky.opacity(0.72))

            TextField("Search products, materials, or sellers", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search products")
                .accessibilityIdentifier("shop.search.field")
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.52), lineWidth: 0.9)
        )
        .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
        .padding(.top, 3)
        .padding(.bottom, 4)
        .background(TBTheme.cloudWhite)
    }

    private var quickFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ShopHighlightFilter.allCases) { filter in
                    Button {
                        selectedHighlight = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                (selectedHighlight == filter ? TBTheme.skyBlue.opacity(0.16) : Color.white.opacity(0.70)),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        selectedHighlight == filter ? TBTheme.icyBlue.opacity(0.35) : Color.white.opacity(0.55),
                                        lineWidth: 1
                                    )
                            )
                            .foregroundStyle(selectedHighlight == filter ? TBTheme.deepSky : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
        }
        .padding(.bottom, 4)
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

    private var shopSnapshotVersion: Int {
        var hasher = Hasher()
        hasher.combine(selectedCategory.id)
        hasher.combine(selectedHighlight.rawValue)
        hasher.combine(normalizedSearchText)
        hasher.combine(catalog.contentRevision)
        hasher.combine(localProducts.productsRevision)

        return hasher.finalize()
    }

    private func computeShopSnapshot() -> ShopSnapshot {
        let storefrontProducts = resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
        let sellerProfilesByID = resolvedSellerProfilesByID(
            storefrontProducts: storefrontProducts,
            remoteProfiles: catalog.sellerProfiles
        )
        let filteredProducts = storefrontProducts.filter { product in
            let matchesCategory = selectedCategory.title == "All" || product.category.rawValue == selectedCategory.title
            let matchesSearch = matchesSearchQuery(product, sellerProfilesByID: sellerProfilesByID)
            return matchesCategory && matchesSearch
        }

        let displayedProducts: [Product]
        switch selectedHighlight {
        case .everything:
            displayedProducts = filteredProducts
        case .latest:
            displayedProducts = filteredProducts.sorted { $0.createdAt > $1.createdAt }
        case .creatorClips:
            let clipped = filteredProducts.filter(\.hasCreatorClip)
            displayedProducts = clipped.isEmpty ? filteredProducts : clipped
        case .priceDrops:
            let dropped = filteredProducts.filter(\.hasPriceDrop)
            displayedProducts = dropped.isEmpty ? filteredProducts : dropped.sorted {
                ($0.previousPriceCents ?? $0.priceCents) > ($1.previousPriceCents ?? $1.priceCents)
            }
        }

        return ShopSnapshot(
            storefrontProducts: storefrontProducts,
            sellerProfilesByID: sellerProfilesByID,
            displayedProducts: displayedProducts
        )
    }

    private func matchesSearchQuery(_ product: Product) -> Bool {
        matchesSearchQuery(product, sellerProfilesByID: sellerProfilesByID)
    }

    private func matchesSearchQuery(
        _ product: Product,
        sellerProfilesByID: [String: SellerProfile]
    ) -> Bool {
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

