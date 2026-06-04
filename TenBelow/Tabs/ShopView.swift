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
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore
    @State private var showCart = false
    @State private var showWishlist = false
    @State private var showSellerFilter = false
    @State private var selectedCategory: TBCategory = tbCategories[0] // All
    @State private var searchText = ""
    @State private var selectedHighlight: ShopBrowseHighlight = .everything
    @State private var selectedSort: ShopSortOption = .recommended
    @State private var selectedSellerId: String?
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
        var sellerFilterOptions: [(id: String, name: String)] = []
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

    private var selectedSellerLabel: String {
        guard let selectedSellerId,
              let match = shopSnapshot.sellerFilterOptions.first(where: { $0.id == selectedSellerId })
        else { return "Seller" }
        return match.name
    }

    private var savedCount: Int {
        buyerEngagement.favoriteProductIDs.count
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
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
                                .frame(height: 142)
                                .padding(.bottom, TopLevelHeaderMetrics.titleArtBottomTuck + 2)
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
                            .padding(.bottom, 4)
                    }
                    .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
                    .padding(.top, TopLevelHeaderMetrics.shopTopInset)
                    .padding(.bottom, TopLevelHeaderMetrics.shopBottomInset)
                    .padding(.horizontal, TopLevelHeaderMetrics.shopOuterHorizontalInset)

                    searchField

                    CategoryFilterBar(
                        categories: tbCategories,
                        selected: $selectedCategory
                    )
                    .padding(.top, TopLevelHeaderMetrics.shopFilterTopInset)
                    .padding(.bottom, 2)

                    sortAndFilterBar

                    quickFilterBar

                    if displayedProducts.isEmpty {
                        VStack(spacing: 14) {
                            Spacer()
                            Image(systemName: emptyStateIcon)
                                .font(.system(size: 36))
                                .foregroundStyle(TBTheme.skyBlue)
                            Text(emptyStateTitle)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(TBTheme.deepSky)
                            Text(emptyStateMessage)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            if selectedHighlight == .saved {
                                Button("Browse all products") {
                                    selectedHighlight = .everything
                                }
                                .buttonStyle(.bordered)
                                .tint(TBTheme.icyBlue)
                            }
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

                HStack(spacing: 8) {
                    if savedCount > 0 {
                        Button {
                            showWishlist = true
                        } label: {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(TBTheme.accent)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Open wishlist, \(savedCount) saved items")
                    }

                    CartButton(itemCount: cart.items.reduce(0) { $0 + $1.quantity }) {
                        showCart = true
                    }
                    .frame(width: 48, height: 44)
                }
                .padding(.trailing, TopLevelChromeMetrics.manualCartTrailingInset)
                .safeAreaPadding(.top, TopLevelChromeMetrics.manualCartTopInset)
            }
            .background(TBTheme.cloudWhite)
            #if os(iOS) || os(visionOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showCart) {
                CartView()
                    .environmentObject(cart)
                    .environmentObject(catalog)
                    .environmentObject(localProducts)
            }
            .navigationDestination(isPresented: $showWishlist) {
                WishlistView()
                    .environmentObject(catalog)
                    .environmentObject(localProducts)
                    .environmentObject(buyerEngagement)
            }
            .sheet(isPresented: $showSellerFilter) {
                ShopSellerFilterSheet(
                    sellers: shopSnapshot.sellerFilterOptions,
                    selectedSellerId: $selectedSellerId
                )
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
                .submitLabel(.search)
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
        .padding(.bottom, 2)
        .background(TBTheme.cloudWhite)
        .zIndex(1)
    }

    private var sortAndFilterBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(ShopSortOption.allCases) { option in
                    Button {
                        selectedSort = option
                    } label: {
                        if selectedSort == option {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                ShopFilterChip(
                    title: selectedSort.shortLabel,
                    systemImage: "arrow.up.arrow.down",
                    isActive: selectedSort != .recommended
                )
            }

            Button {
                showSellerFilter = true
            } label: {
                ShopFilterChip(
                    title: selectedSellerId == nil ? "Seller" : selectedSellerLabel,
                    systemImage: "storefront",
                    isActive: selectedSellerId != nil
                )
            }

            if selectedSellerId != nil {
                Button {
                    selectedSellerId = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear seller filter")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
        .padding(.bottom, 2)
        .background(TBTheme.cloudWhite)
    }

    private var quickFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ShopBrowseHighlight.allCases) { filter in
                    Button {
                        selectedHighlight = filter
                    } label: {
                        HStack(spacing: 5) {
                            Text(filter.rawValue)
                            if filter == .saved, savedCount > 0 {
                                Text("\(savedCount)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        selectedHighlight == filter ? Color.white.opacity(0.28) : TBTheme.accent.opacity(0.14),
                                        in: Capsule()
                                    )
                            }
                        }
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
        .padding(.bottom, 2)
        .background(TBTheme.cloudWhite)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var emptyStateIcon: String {
        selectedHighlight == .saved ? "heart" : "square.grid.2x2"
    }

    private var emptyStateTitle: String {
        if selectedHighlight == .saved {
            return "Wishlist is empty"
        }
        return normalizedSearchText.isEmpty ? "No products to show" : "No matches found"
    }

    private var emptyStateMessage: String {
        if selectedHighlight == .saved {
            return "Save items with the heart button while you browse."
        }
        if !normalizedSearchText.isEmpty {
            return "Try a different word, seller, or category."
        }
        if selectedSellerId != nil {
            return "This seller has no listings that match your filters."
        }
        return catalog.lastLoadError ?? "Try another category or check back soon."
    }

    private var shopSnapshotVersion: Int {
        var hasher = Hasher()
        hasher.combine(selectedCategory.id)
        hasher.combine(selectedHighlight.rawValue)
        hasher.combine(selectedSort.rawValue)
        hasher.combine(selectedSellerId)
        hasher.combine(normalizedSearchText)
        hasher.combine(catalog.contentRevision)
        hasher.combine(localProducts.productsRevision)
        hasher.combine(buyerEngagement.favoriteProductIDs.sorted().joined(separator: "|"))
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

        var filtered = ShopBrowseFilters.filterByCategory(storefrontProducts, category: selectedCategory)
        filtered = ShopBrowseFilters.filterBySearch(filtered, query: normalizedSearchText, sellerProfilesByID: sellerProfilesByID)
        filtered = ShopBrowseFilters.filterBySeller(filtered, sellerId: selectedSellerId)

        let sellerFilterOptions = ShopBrowseFilters.sellerOptions(
            from: ShopBrowseFilters.filterByCategory(storefrontProducts, category: selectedCategory),
            profilesByID: sellerProfilesByID
        )

        let highlighted = ShopBrowseFilters.applyHighlight(
            filtered,
            highlight: selectedHighlight,
            favoriteProductIDs: buyerEngagement.favoriteProductIDs
        )
        let displayedProducts = ShopBrowseFilters.applySort(
            highlighted,
            sort: selectedSort,
            highlight: selectedHighlight
        )

        return ShopSnapshot(
            storefrontProducts: storefrontProducts,
            sellerProfilesByID: sellerProfilesByID,
            displayedProducts: displayedProducts,
            sellerFilterOptions: sellerFilterOptions
        )
    }
}

private struct ShopFilterChip: View {
    let title: String
    let systemImage: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? TBTheme.deepSky : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            (isActive ? TBTheme.skyBlue.opacity(0.16) : Color.white.opacity(0.72)),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(isActive ? TBTheme.icyBlue.opacity(0.35) : Color.white.opacity(0.55), lineWidth: 1)
        )
    }
}

private struct ShopSellerFilterSheet: View {
    let sellers: [(id: String, name: String)]
    @Binding var selectedSellerId: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedSellerId = nil
                    dismiss()
                } label: {
                    HStack {
                        Text("All sellers")
                        Spacer()
                        if selectedSellerId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(TBTheme.icyBlue)
                        }
                    }
                }

                ForEach(sellers, id: \.id) { seller in
                    Button {
                        selectedSellerId = seller.id
                        dismiss()
                    } label: {
                        HStack {
                            Text(seller.name)
                            Spacer()
                            if selectedSellerId == seller.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(TBTheme.icyBlue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter by seller")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
