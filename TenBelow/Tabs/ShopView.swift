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
    @State private var showSellerFilter = false
    @State private var showCollapsedFilters = false
    @State private var selectedCategory: TBCategory = tbCategories[0] // All
    @State private var searchText = ""
    @State private var selectedHighlight: ShopBrowseHighlight = .everything
    @State private var selectedSort: ShopSortOption = .recommended
    @State private var selectedSellerId: String?
    @State private var shopSnapshotCache = ShopSnapshotCache()

    private var shopGridColumns: [GridItem] {
        let spacing = TopLevelHeaderMetrics.shopGridSpacing
        return [
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing)
        ]
    }

    private struct ShopSnapshot {
        var storefrontProducts: [Product] = []
        var sellerProfilesByID: [String: SellerProfile] = [:]
        var displayedProducts: [Product] = []
        var sellerFilterOptions: [(id: String, name: String)] = []
    }

    /// Reference-type memo slot so a cache miss is filled during the same body evaluation.
    /// The previous `@State` cache was only written by an async task, so on a miss every
    /// snapshot consumer (grid, filters, sheets) recomputed the full filter pipeline.
    private final class ShopSnapshotCache {
        var snapshot = ShopSnapshot()
        var version: Int?
    }

    private var shopSnapshot: ShopSnapshot {
        let version = shopSnapshotVersion
        if shopSnapshotCache.version == version {
            return shopSnapshotCache.snapshot
        }
        let snapshot = computeShopSnapshot()
        shopSnapshotCache.snapshot = snapshot
        shopSnapshotCache.version = version
        return snapshot
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
                    VStack(alignment: .center, spacing: 0) {
                        SnowfallTitleContainer(
                            cornerRadius: 26,
                            horizontalPadding: 12,
                            verticalPadding: 4,
                            flakeCount: 78,
                            effectHorizontalInset: 16,
                            effectVerticalInset: 10
                        ) {
                            Image("ShopTitle")
                                .resizable()
                                .scaledToFit()
                                .frame(height: TopLevelHeaderMetrics.shopTitleImageHeight)
                                .scaleEffect(
                                    TopLevelHeaderMetrics.shopTitleScale,
                                    anchor: .bottom
                                )
                                .padding(.bottom, TopLevelHeaderMetrics.shopTitleBottomTuck)
                                .accessibilityLabel("Shop")
                                .accessibilityAddTraits(.isHeader)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        HStack(spacing: 6) {
                            Image(systemName: "snowflake")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(red: 42 / 255, green: 109 / 255, blue: 181 / 255))
                            Text("Everything is $10 and under.")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 26 / 255, green: 95 / 255, blue: 168 / 255))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Color(red: 168 / 255, green: 212 / 255, blue: 245 / 255).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .shadow(color: .white.opacity(0.35), radius: 1, y: 1)
                        .padding(.bottom, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
                    .padding(.top, TopLevelHeaderMetrics.shopTopInset)
                    .padding(.bottom, TopLevelHeaderMetrics.shopBottomInset)

                    searchField

                    collapsedFilterSection
                    .padding(.top, TopLevelHeaderMetrics.shopFilterRowSpacing)
                    .padding(.bottom, TopLevelHeaderMetrics.shopFilterRowSpacing)

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
                                LazyVGrid(columns: shopGridColumns, spacing: TopLevelHeaderMetrics.shopGridSpacing) {
                                    ForEach(displayedProducts) { product in
                                        ProductCard(
                                            product: product,
                                            seller: sellerProfilesByID[product.sellerId],
                                            allProducts: storefrontProducts,
                                            style: .compact,
                                            showsAccentBorder: true
                                        )
                                    }
                                }
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: geometry.size.height,
                                    alignment: .topLeading
                                )
                                .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
                                .padding(.top, TopLevelHeaderMetrics.shopGridTopInset)
                                .padding(.bottom, TopLevelHeaderMetrics.shopScrollBottomPadding(safeAreaBottom: geometry.safeAreaInsets.bottom))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(TBFrostBackground())

                CartButton(itemCount: cart.items.reduce(0) { $0 + $1.quantity }) {
                    showCart = true
                }
                .frame(width: 48, height: 44)
                .padding(.trailing, TopLevelChromeMetrics.manualCartTrailingInset)
                .safeAreaPadding(.top, TopLevelChromeMetrics.manualCartTopInset)
            }
            .background(TBFrostBackground())
            #if os(iOS) || os(visionOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showCart) {
                CartView()
                    .environmentObject(cart)
                    .environmentObject(catalog)
                    .environmentObject(localProducts)
            }
            .sheet(isPresented: $showSellerFilter) {
                ShopSellerFilterSheet(
                    sellers: shopSnapshot.sellerFilterOptions,
                    selectedSellerId: $selectedSellerId
                )
            }
            .sheet(isPresented: $showCollapsedFilters) {
                ShopCollapsedFiltersSheet(
                    selectedSort: $selectedSort,
                    selectedHighlight: $selectedHighlight,
                    selectedSellerId: $selectedSellerId,
                    sellers: shopSnapshot.sellerFilterOptions,
                    savedCount: savedCount
                )
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
                .strokeBorder(TBTheme.frostEdge, lineWidth: 1.0)
        )
        .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
        .padding(.bottom, TopLevelHeaderMetrics.shopFilterRowSpacing)
        .background(TBTheme.frostScreenTop)
        .zIndex(1)
    }

    private var collapsedFilterSection: some View {
        HStack(spacing: 8) {
            ShopCategoryFilterBar(
                categories: tbCategories,
                selected: $selectedCategory
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showCollapsedFilters = true
            } label: {
                HStack(spacing: 5) {
                    Text("Filters")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color(red: 42 / 255, green: 109 / 255, blue: 181 / 255))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.88), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(TBTheme.frostEdge, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
        .background(TBTheme.frostScreenTop)
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
        .background(TBTheme.frostScreenTop)
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
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            selectedHighlight == filter ? TBTheme.skyBlue.opacity(0.16) : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    selectedHighlight == filter
                                        ? AnyShapeStyle(TBTheme.icyBlue.opacity(0.35))
                                        : AnyShapeStyle(TBTheme.frostEdge),
                                    lineWidth: 1
                                )
                        )
                        .foregroundStyle(
                            selectedHighlight == filter
                                ? TBTheme.deepSky
                                : Color(red: 74 / 255, green: 127 / 255, blue: 170 / 255).opacity(0.82)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
        }
        .background(TBTheme.frostScreenTop)
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

private struct ShopCategoryFilterBar: View {
    let categories: [TBCategory]
    @Binding var selected: TBCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(categories) { category in
                    Button {
                        selected = category
                    } label: {
                        ShopCategoryChip(
                            title: category.title,
                            icon: category.icon,
                            isSelected: selected == category
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct ShopCategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18, height: 18)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? Color(red: 42 / 255, green: 109 / 255, blue: 181 / 255)
                : Color.white,
            in: Capsule(style: .continuous)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    isSelected ? AnyShapeStyle(Color.white.opacity(0.5)) : AnyShapeStyle(TBTheme.frostEdge),
                    lineWidth: 0.8
                )
        )
        .foregroundStyle(
            isSelected
                ? Color.white
                : Color(red: 74 / 255, green: 127 / 255, blue: 170 / 255)
        )
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
        .contentShape(Capsule())
        .animation(.easeInOut(duration: 0.18), value: isSelected)
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
        .foregroundStyle(Color(red: 74 / 255, green: 127 / 255, blue: 170 / 255))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Color(red: 200 / 255, green: 220 / 255, blue: 240 / 255).opacity(0.4),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    isActive
                        ? AnyShapeStyle(Color(red: 74 / 255, green: 127 / 255, blue: 170 / 255).opacity(0.28))
                        : AnyShapeStyle(Color.white.opacity(0.55)),
                    lineWidth: 1
                )
        )
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.origins[index].x, y: bounds.minY + result.origins[index].y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + lineHeight), origins)
    }
}

private struct ShopCollapsedFiltersSheet: View {
    @Binding var selectedSort: ShopSortOption
    @Binding var selectedHighlight: ShopBrowseHighlight
    @Binding var selectedSellerId: String?
    let sellers: [(id: String, name: String)]
    let savedCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    filterSectionTitle("Sort")
                    optionWrap {
                        ForEach(ShopSortOption.allCases) { option in
                            sheetOptionButton(
                                title: option.rawValue,
                                isSelected: selectedSort == option
                            ) {
                                selectedSort = option
                            }
                        }
                    }

                    filterSectionTitle("Browse")
                    optionWrap {
                        ForEach(ShopBrowseHighlight.allCases) { filter in
                            sheetOptionButton(
                                title: filter == .saved && savedCount > 0 ? "\(filter.rawValue) \(savedCount)" : filter.rawValue,
                                isSelected: selectedHighlight == filter
                            ) {
                                selectedHighlight = filter
                            }
                        }
                    }

                    filterSectionTitle("Seller")
                    optionWrap {
                        sheetOptionButton(
                            title: "All sellers",
                            isSelected: selectedSellerId == nil
                        ) {
                            selectedSellerId = nil
                        }

                        ForEach(sellers, id: \.id) { seller in
                            sheetOptionButton(
                                title: seller.name,
                                isSelected: selectedSellerId == seller.id
                            ) {
                                selectedSellerId = seller.id
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(TBFrostBackground())
            .navigationTitle("Filters")
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

    private func filterSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 42 / 255, green: 109 / 255, blue: 181 / 255))
            .textCase(.uppercase)
    }

    private func optionWrap<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        FlowLayout(spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sheetOptionButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white : Color(red: 74 / 255, green: 127 / 255, blue: 170 / 255))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? Color(red: 42 / 255, green: 109 / 255, blue: 181 / 255)
                        : Color.white.opacity(0.78),
                    in: Capsule(style: .continuous)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? AnyShapeStyle(Color.white.opacity(0.55)) : AnyShapeStyle(TBTheme.frostEdge),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
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
