//
//  HomeView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import Combine

struct HomeView: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @EnvironmentObject private var orderStore: OrderStore
    @EnvironmentObject private var notifications: NotificationStore
    @AppStorage("userRole") private var userRole = ""
    @AppStorage("buyerFullName") private var buyerFullName = ""
    @AppStorage("buyerAccountCreated") private var buyerAccountCreated = false
    @AppStorage("sellerSellerId") private var sellerId = ""
    @AppStorage("sellerBusinessName") private var sellerBusinessName = ""
    @State private var showCart = false
    @State private var liveDrop: CurrentDropResponse?
    @State private var selectedFeaturedCreator: SellerProfile?
    @State private var featuredRotationIndex = 0
    @State private var creatorRotationIndex = 0
    @State private var cachedFeaturedProducts: [Product] = []
    @State private var lastLiveDropRefresh = Date.distantPast
    @State private var isLiveDropRefreshInFlight = false
    @State private var isHomeVisible = false
    @State private var catalogCache = HomeCatalogCache()
    private let rotationInterval: TimeInterval = 120
    private let rotationTimer = Timer.publish(every: 120, on: .main, in: .common).autoconnect()

    /// Shared horizontal inset and vertical rhythm for the home screen.
    private enum HomeMetrics {
        static let pageInset = TBTheme.spacingXL
        // Give section titles a little more breathing room above cards/banners.
        static let titleToContent = TBTheme.spacingSM + 4
        /// Hero mark size; paired with tighter snowfall padding so layout below doesn’t shift too far.
        static let logoImageHeight: CGFloat = 170
        static let logoVisualScale: CGFloat = 1.03
        static let logoTopOffset: CGFloat = -15
        static let logoSnowfallVerticalPadding: CGFloat = 1
        static let logoToDealSpacing: CGFloat = 2
        /// Clear separation so the favorites strip (and its pill title) never visually collides with the deal hero.
        static let dealToFavoritesSpacing: CGFloat = 24
        /// Gap between Fresh favorites and Maker spotlight (fixed — not device-dependent).
        static let favoritesToSpotlightSpacing: CGFloat = 16
        /// Keeps the spotlight card off the tab bar when the catalog finishes loading.
        static let spotlightBottomSpacing: CGFloat = 0
        /// Gap between Maker Spotlight and the floating tab bar (tight — card sits just above the bar).
        static let spotlightToTabSpacing: CGFloat = 4
        /// Scroll bottom padding above the tab bar on Home only.
        static let tabBarScrollClearance: CGFloat = 16
        /// Reserved block height so the screen does not jump when live seller profiles arrive.
        static let spotlightBlockMinHeight: CGFloat = 118
        /// Fixed row height for the favorites carousel (blended cards size to content otherwise).
        static let freshFavoritesRowHeight: CGFloat = 228
        /// Space between the spotlight title pill and the card (pulled slightly up so the pill clears the hero).
        static let spotlightTitleToCard: CGFloat = 9
        static let dealTitleTopOffset: CGFloat = -4
        static let favoritesTitleTopInset: CGFloat = 14
        static let favoritesTitleToCardsSpacing: CGFloat = TBTheme.spacingSM
        /// Former optical nudge for plain `Text`; folded into layout padding so the pill doesn’t draw over the hero (`offset` doesn’t expand layout).
        static let favoritesTitleVisualDrop: CGFloat = 7
        /// Horizontal strip shows up to this many cards; ranking pool may be larger for rotation.
        static let freshFavoritesMaxStripCards = 6

        static func dealBannerHeight(for contentWidth: CGFloat) -> CGFloat {
            return min(max(contentWidth * 0.30, 118), 132)
        }

        static func freshFavoriteCardWidth(for contentWidth: CGFloat) -> CGFloat {
            min(max(contentWidth * 0.417, 150), 166)
        }
    }

    private struct HomeLayoutProfile {
        let logoImageHeight: CGFloat
        let logoTopOffset: CGFloat
        let logoToDealSpacing: CGFloat
        let dealToFavoritesSpacing: CGFloat
        let favoritesTitleTopInset: CGFloat
        let favoritesTitleVisualDrop: CGFloat
        let favoritesRowHeight: CGFloat
        let favoritesToSpotlightSpacing: CGFloat
        let spotlightTitleToCard: CGFloat
        let spotlightBottomSpacing: CGFloat
        let spotlightToTabSpacing: CGFloat
        let spotlightBlockMinHeight: CGFloat
        let bottomClearanceExtra: CGFloat

        static func resolved(for availableHeight: CGFloat) -> HomeLayoutProfile {
            if availableHeight < 700 {
                return HomeLayoutProfile(
                    logoImageHeight: 128,
                    logoTopOffset: -8,
                    logoToDealSpacing: 1,
                    dealToFavoritesSpacing: 18,
                    favoritesTitleTopInset: 5,
                    favoritesTitleVisualDrop: 3,
                    favoritesRowHeight: 214,
                    favoritesToSpotlightSpacing: 8,
                    spotlightTitleToCard: 5,
                    spotlightBottomSpacing: 0,
                    spotlightToTabSpacing: 2,
                    spotlightBlockMinHeight: 92,
                    bottomClearanceExtra: 6
                )
            }

            if availableHeight < 760 {
                return HomeLayoutProfile(
                    logoImageHeight: 146,
                    logoTopOffset: -10,
                    logoToDealSpacing: 2,
                    dealToFavoritesSpacing: 20,
                    favoritesTitleTopInset: 6,
                    favoritesTitleVisualDrop: 4,
                    favoritesRowHeight: 218,
                    favoritesToSpotlightSpacing: 13,
                    spotlightTitleToCard: 6,
                    spotlightBottomSpacing: 0,
                    spotlightToTabSpacing: 3,
                    spotlightBlockMinHeight: 96,
                    bottomClearanceExtra: 6
                )
            }

            if availableHeight < 850 {
                return HomeLayoutProfile(
                    logoImageHeight: 162,
                    logoTopOffset: -12,
                    logoToDealSpacing: 2,
                    dealToFavoritesSpacing: 24,
                    favoritesTitleTopInset: 10,
                    favoritesTitleVisualDrop: 5,
                    favoritesRowHeight: 218,
                    favoritesToSpotlightSpacing: 18,
                    spotlightTitleToCard: 8,
                    spotlightBottomSpacing: 0,
                    spotlightToTabSpacing: 4,
                    spotlightBlockMinHeight: 108,
                    bottomClearanceExtra: 0
                )
            }

            return HomeLayoutProfile(
                logoImageHeight: HomeMetrics.logoImageHeight,
                logoTopOffset: HomeMetrics.logoTopOffset,
                logoToDealSpacing: HomeMetrics.logoToDealSpacing,
                dealToFavoritesSpacing: HomeMetrics.dealToFavoritesSpacing,
                favoritesTitleTopInset: HomeMetrics.favoritesTitleTopInset,
                favoritesTitleVisualDrop: HomeMetrics.favoritesTitleVisualDrop,
                favoritesRowHeight: HomeMetrics.freshFavoritesRowHeight,
                favoritesToSpotlightSpacing: HomeMetrics.favoritesToSpotlightSpacing + 6,
                spotlightTitleToCard: HomeMetrics.spotlightTitleToCard,
                spotlightBottomSpacing: HomeMetrics.spotlightBottomSpacing,
                spotlightToTabSpacing: HomeMetrics.spotlightToTabSpacing,
                spotlightBlockMinHeight: HomeMetrics.spotlightBlockMinHeight,
                bottomClearanceExtra: 0
            )
        }
    }

    /// Compact frost capsule for home section headings.
    private struct HomeSectionTitlePill: View {
        enum Style {
            /// Default strip titles (e.g. Fresh favorites).
            case standard
            /// Slightly larger copy and padding so the label carries more visual weight without shifting layout.
            case spotlight
        }

        let title: String
        var style: Style = .standard

        private var titleFont: Font {
            switch style {
            case .standard:
                return .system(size: 15, weight: .semibold, design: .rounded)
            case .spotlight:
                return .system(size: 18, weight: .semibold, design: .rounded)
            }
        }

        private var horizontalPadding: CGFloat {
            switch style {
            case .standard: return 10
            case .spotlight: return 16
            }
        }

        private var verticalPadding: CGFloat {
            switch style {
            case .standard: return 4
            case .spotlight: return 10
            }
        }

        private var strokeWidth: CGFloat {
            switch style {
            case .standard: return 0.75
            case .spotlight: return 0.85
            }
        }

        private var iconName: String {
            title.localizedCaseInsensitiveContains("maker") ? "flashlight.on.fill" : "snowflake"
        }

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: style == .spotlight ? 12 : 10, weight: .semibold))
                    .foregroundStyle(TBTheme.frostGlow)

                Text(title)
                    .font(titleFont)
                    .foregroundStyle(TBTheme.icyBlue)
            }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.78),
                                    TBTheme.skyLight.opacity(0.42),
                                    TBTheme.frostGlow.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(TBTheme.frostEdge, lineWidth: strokeWidth)
                )
                .shadow(color: TBTheme.deepSky.opacity(0.06), radius: style == .spotlight ? 3 : 2, y: style == .spotlight ? 2 : 1)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// These derived collections are expensive (full catalog merge + per-seller profile
    /// resolution), and Home re-renders on rotation timers. Memoize per catalog revision so
    /// repeated body evaluations and per-card lookups stay O(1).
    private var catalogSnapshot: HomeCatalogSnapshot {
        let key = "\(catalog.contentRevision)|\(localProducts.productsRevision)|\(catalog.isUsingCachedData)"
        if let cached = catalogCache.snapshot, cached.key == key {
            return cached
        }

        let resolvedProducts = computeProductsForSnapshot()
        let snapshot = HomeCatalogSnapshot(
            key: key,
            products: resolvedProducts,
            freshFavoritesCatalog: computeFreshFavoritesCatalog(base: resolvedProducts),
            remoteProfiles: catalog.sellerProfiles
        )
        catalogCache.snapshot = snapshot
        return snapshot
    }

    private var products: [Product] {
        catalogSnapshot.products
    }

    private var freshFavoritesCatalog: [Product] {
        catalogSnapshot.freshFavoritesCatalog
    }

    private var sellerProfilesByID: [String: SellerProfile] {
        catalogSnapshot.sellerProfilesByID
    }

    private var freshFavoritesSellerProfilesByID: [String: SellerProfile] {
        catalogSnapshot.freshFavoritesSellerProfilesByID
    }

    private func computeProductsForSnapshot() -> [Product] {
        let resolvedProducts = resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
#if DEBUG
        return resolvedProducts
#else
        return resolvedProducts.filter(CatalogSeedPolicy.isRealStorefrontProduct)
#endif
    }

    /// Fresh favorites only: keep mock filler for thin live catalogs, but do not re-add local seller drafts after
    /// the backend catalog has loaded. Deleted/archived server products must disappear everywhere.
    private func computeFreshFavoritesCatalog(base: [Product]) -> [Product] {
        if base.count >= HomeMetrics.freshFavoritesMaxStripCards { return base }

        var seen = Set(base.map(\.id))
        var merged = base

        func appendUnique(_ candidates: [Product]) {
            for p in candidates {
                guard merged.count < 32 else { return }
                if seen.insert(p.id).inserted {
                    merged.append(p)
                }
            }
        }

        if catalog.isUsingCachedData {
            appendUnique(localProducts.products)
        }
        #if DEBUG
        if merged.count < HomeMetrics.freshFavoritesMaxStripCards {
            appendUnique(MockData.products)
        }
        #endif
        return merged
    }

    private var orders: [Order] {
        orderStore.orders
    }

    @ViewBuilder
    private var profileDestination: some View {
        if userRole == "seller" {
            if let sellerStoreProfile {
                SellerStorePreviewView(
                    seller: sellerStoreProfile,
                    products: products
                )
            } else {
                SellerProfileView()
            }
        } else {
            BuyerProfileView()
        }
    }

    private var sellerStoreProfile: SellerProfile? {
        let trimmedSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSellerId.isEmpty else { return nil }

        return resolvedSellerProfile(
            sellerId: trimmedSellerId,
            storefrontProducts: products.filter { $0.sellerId == trimmedSellerId },
            remoteProfiles: catalog.sellerProfiles
        ) ?? .previewProfile(
            sellerId: trimmedSellerId,
            businessName: sellerBusinessName
        )
    }

    private var profileToolbarIcon: some View {
        Group {
            // Single-letter initials read as stray glyphs next to the bell; prefer the icon until we have ≥2 letters.
            if userRole == "buyer", buyerAccountCreated, buyerInitials.count >= 2 {
                Text(buyerInitials)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    private var buyerInitials: String {
        let trimmedName = buyerFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmedName.split(whereSeparator: \.isWhitespace)
        let letters = parts.prefix(2).compactMap { $0.first.map { String($0).uppercased() } }
        return letters.joined()
    }

    private var excludedFeaturedProductIDs: Set<String> {
        if let liveDrop, liveDrop.active {
            return Set(liveDrop.products.map(\.id))
        }

        return []
    }

    private var featuredProducts: [Product] {
        if !cachedFeaturedProducts.isEmpty {
            return cachedFeaturedProducts
        }

        return computeFeaturedProducts()
    }

    private func computeFeaturedProducts() -> [Product] {
        let nonDropProducts = products.filter { !excludedFeaturedProductIDs.contains($0.id) }
        let source = nonDropProducts.isEmpty ? products : nonDropProducts
        let salesCounts = productSalesCounts

        let sellerBuckets = Dictionary(grouping: source, by: \.sellerId)
            .mapValues { sellerProducts in
                sellerProducts.sorted { lhs, rhs in
                    let lhsScore = dealOfDayPriorityScore(lhs, salesCounts: salesCounts)
                    let rhsScore = dealOfDayPriorityScore(rhs, salesCounts: salesCounts)

                    if lhsScore == rhsScore {
                        if lhs.priceCents == rhs.priceCents {
                            return lhs.name < rhs.name
                        }
                        return lhs.priceCents < rhs.priceCents
                    }

                    return lhsScore < rhsScore
                }
            }

        let sellerOrder = sellerBuckets.keys.sorted { lhs, rhs in
            let lhsTraffic = sellerProfilesByID[lhs]?.pageViewCount ?? 0
            let rhsTraffic = sellerProfilesByID[rhs]?.pageViewCount ?? 0
            if lhsTraffic == rhsTraffic {
                return lhs < rhs
            }
            return lhsTraffic < rhsTraffic
        }

        var nextIndexBySellerID = Dictionary(
            uniqueKeysWithValues: sellerOrder.map { ($0, 0) }
        )
        var rotation: [Product] = []
        var appendedProductIDs = Set<String>()

        while rotation.count < source.count {
            var appendedInPass = false

            for sellerID in sellerOrder {
                guard
                    let sellerProducts = sellerBuckets[sellerID],
                    let nextIndex = nextIndexBySellerID[sellerID],
                    nextIndex < sellerProducts.count
                else {
                    continue
                }

                let nextProduct = sellerProducts[nextIndex]
                nextIndexBySellerID[sellerID] = nextIndex + 1

                if appendedProductIDs.insert(nextProduct.id).inserted {
                    rotation.append(nextProduct)
                    appendedInPass = true
                }
            }

            if !appendedInPass {
                break
            }
        }

        return rotation.isEmpty ? source : rotation
    }

    /// Pool for Fresh favorites ranking. Usually excludes the current Deal of the Day so sections differ,
    /// but when that would leave fewer than two items while more storefront products exist, include all
    /// eligible products so the horizontal carousel still shows multiple cards (same catalog the cart uses).
    private var freshFavoriteRankingPool: [Product] {
        let catalog = freshFavoritesCatalog
        let nonDropProducts = catalog.filter { !excludedFeaturedProductIDs.contains($0.id) }
        let source = nonDropProducts.isEmpty ? catalog : nonDropProducts
        guard let featuredProductID = featuredProduct?.id else { return source }

        let withoutDealOfDay = source.filter { $0.id != featuredProductID }
        if withoutDealOfDay.isEmpty { return source }
        // Avoid a single-card carousel when the deal is eating the only other listing(s).
        if withoutDealOfDay.count < 2, source.count > withoutDealOfDay.count {
            return source
        }
        return withoutDealOfDay
    }

    private var freshFavoriteProducts: [Product] {
        let rankingPool = freshFavoriteRankingPool
        let salesCounts = productSalesCounts

        let ranked = rankingPool.sorted { lhs, rhs in
            let lhsScore = freshFavoritePriorityScore(lhs, salesCounts: salesCounts)
            let rhsScore = freshFavoritePriorityScore(rhs, salesCounts: salesCounts)

            if lhsScore == rhsScore {
                if lhs.favoriteCount == rhs.favoriteCount {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.favoriteCount > rhs.favoriteCount
            }

            return lhsScore > rhsScore
        }

        guard !ranked.isEmpty else { return [] }
        let startIndex = freshFavoritesRotationOffset % ranked.count
        return Array(ranked[startIndex...] + ranked[..<startIndex])
    }

    private var featuredProductsTaskKey: String {
        "\(catalog.contentRevision)|\(localProducts.productsRevision)|\(liveDrop?.active ?? false)"
    }

    private func refreshFeaturedProductsCache() {
        let latest = computeFeaturedProducts()
        cachedFeaturedProducts = latest

        if latest.isEmpty {
            featuredRotationIndex = 0
        } else {
            featuredRotationIndex %= latest.count
        }
    }

    private var spotlightCreators: [SellerProfile] {
        let sellerIDs = Set(products.map(\.sellerId))

        return sellerIDs
            .compactMap { sellerProfilesByID[$0] }
            .sorted { lhs, rhs in
                let lhsScore = creatorSpotlightScore(lhs)
                let rhsScore = creatorSpotlightScore(rhs)

                if lhsScore == rhsScore {
                    return lhs.displayName < rhs.displayName
                }

                return lhsScore > rhsScore
            }
    }

    private var featuredCreator: SellerProfile? {
        guard !spotlightCreators.isEmpty else { return nil }
        return spotlightCreators[creatorRotationIndex % spotlightCreators.count]
    }

    private var featuredProduct: Product? {
        guard !featuredProducts.isEmpty else { return nil }
        return featuredProducts[featuredRotationIndex % featuredProducts.count]
    }

    private var freshFavoritesRotationOffset: Int {
        let poolSize = max(freshFavoriteProductsCountForRotation, 1)
        return (featuredRotationIndex + creatorRotationIndex) % poolSize
    }

    private var freshFavoriteProductsCountForRotation: Int {
        max(freshFavoriteRankingPool.count, 0)
    }

    /// Products for the horizontal Fresh favorites strip (up to six). When the remote catalog is sparse, fill from locally seeded products.
    private var freshFavoritesDisplayProducts: [Product] {
        let maxCards = HomeMetrics.freshFavoritesMaxStripCards
        let primary = freshFavoriteProducts
        var seen = Set<String>()
        var merged: [Product] = []
        for p in primary {
            guard merged.count < maxCards else { break }
            if seen.insert(p.id).inserted {
                merged.append(p)
            }
        }

        if merged.count < maxCards {
            let salesCounts = productSalesCounts
            let filler = freshFavoritesCatalog
                .filter { !seen.contains($0.id) }
                .sorted { lhs, rhs in
                    let l = freshFavoritePriorityScore(lhs, salesCounts: salesCounts)
                    let r = freshFavoritePriorityScore(rhs, salesCounts: salesCounts)
                    if l == r {
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    return l > r
                }
            for p in filler {
                guard merged.count < maxCards else { break }
                if seen.insert(p.id).inserted {
                    merged.append(p)
                }
            }
        }

        return merged
    }

    private func products(for seller: SellerProfile) -> [Product] {
        products.filter { $0.sellerId == seller.id }
    }

    private var productSalesCounts: [String: Int] {
        orders
            .flatMap(\.shipments)
            .flatMap(\.items)
            .reduce(into: [:]) { counts, item in
                counts[item.productId, default: 0] += item.quantity
            }
    }

    private func creatorSpotlightScore(_ seller: SellerProfile) -> Double {
        let likes = Double(seller.likeCount)
        let traffic = Double(seller.pageViewCount)
        let orders = Double(seller.orderCount)
        let ratingLift = seller.rating * 220
        let reviewTrust = Double(seller.positiveReviewCount) * 4.0
        let verificationBoost = seller.showsVerifiedBadge ? 220.0 : 0.0
        return traffic * 0.45 + likes * 1.2 + orders * 30 + ratingLift + reviewTrust + verificationBoost
    }

    // Sales counts are passed in so sorts build the dictionary once instead of
    // re-scanning every order shipment per comparison.
    private func dealOfDayPriorityScore(_ product: Product, salesCounts: [String: Int]) -> Double {
        let salesCount = Double(salesCounts[product.id] ?? 0)
        let favorites = Double(product.favoriteCount)
        let productViews = Double(product.pageViewCount)
        let sellerTraffic = Double(sellerProfilesByID[product.sellerId]?.pageViewCount ?? 0)
        return salesCount * 45 + favorites * 8 + productViews * 0.35 + sellerTraffic * 0.05
    }

    private func freshFavoritePriorityScore(_ product: Product, salesCounts: [String: Int]) -> Double {
        let salesCount = Double(salesCounts[product.id] ?? 0)
        let favorites = Double(product.favoriteCount)
        let sellerTraffic = Double(sellerProfilesByID[product.sellerId]?.pageViewCount ?? 0)
        let sellerOrders = Double(sellerProfilesByID[product.sellerId]?.orderCount ?? 0)
        let priceWeight = Double(product.priceCents) / 100.0
        let productViews = Double(product.pageViewCount)
        let attentionWithoutPurchase = max(productViews - (salesCount * 3), 0)
        return favorites * 16
            + attentionWithoutPurchase * 0.8
            + sellerTraffic * 0.08
            + sellerOrders * 1.5
            + priceWeight
            - salesCount * 22
    }

    private func seedRotations() {
        let spotlightCount = max(spotlightCreators.count, 1)
        let featuredCount = max(featuredProducts.count, 1)
        let timeBucket = Int(Date().timeIntervalSinceReferenceDate / rotationInterval)

        creatorRotationIndex = timeBucket % spotlightCount
        featuredRotationIndex = timeBucket % featuredCount
    }

    private func advanceRotations() {
        if spotlightCreators.count > 1 {
            creatorRotationIndex = (creatorRotationIndex + 1) % spotlightCreators.count
        }

        if featuredProducts.count > 1 {
            featuredRotationIndex = (featuredRotationIndex + 1) % featuredProducts.count
        }
    }

    private func freshFavoritesSection(cardWidth: CGFloat, pageInset: CGFloat, layout: HomeLayoutProfile) -> some View {
        return VStack(alignment: .leading, spacing: HomeMetrics.favoritesTitleToCardsSpacing) {
            HomeSectionTitlePill(title: "Fresh Favorites")
                .padding(.top, layout.favoritesTitleTopInset + layout.favoritesTitleVisualDrop)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TBTheme.spacingLG + 2) {
                    ForEach(freshFavoritesDisplayProducts) { product in
                        ProductCard(
                            product: product,
                            seller: freshFavoritesSellerProfilesByID[product.sellerId],
                            allProducts: freshFavoritesCatalog,
                            style: .blended,
                            showsAccentBorder: true
                        )
                        .frame(width: cardWidth)
                        .overlay(
                            RoundedRectangle(cornerRadius: TBTheme.radiusLG, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                                .shadow(color: TBTheme.deepSky.opacity(0.08), radius: 5, x: 0, y: 2)
                        )
                        .overlay(alignment: .topLeading) {
                            if product.id == freshFavoritesDisplayProducts.first?.id {
                                Text("❄️ New Drop")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(TBTheme.deepSky)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(TBTheme.skyLight.opacity(0.88), in: Capsule(style: .continuous))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.62), lineWidth: 1)
                                    )
                                    .padding(8)
                            }
                        }
                    }
                }
                .padding(.trailing, pageInset)
                .padding(.bottom, 0)
            }
            // Horizontal `ScrollView` can add implicit scroll-content margins (extra air below the row).
            .contentMargins(.vertical, 0, for: .scrollContent)
            // Horizontal scroll content must not widen the home column; otherwise sections below
            // (e.g. Maker spotlight) lay out at the inflated width and appear shifted on screen.
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: layout.favoritesRowHeight, alignment: .top)
        }
    }

    private func makerSpotlightSection(_ creator: SellerProfile, layout: HomeLayoutProfile) -> some View {
        return VStack(alignment: .leading, spacing: layout.spotlightTitleToCard) {
            HomeSectionTitlePill(title: "Maker Spotlight")

            CreatorSpotlightCard(
                creator: creator,
                onOpenStore: {
                    selectedFeaturedCreator = creator
                }
            )
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(.bottom, layout.spotlightBottomSpacing)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func homeScrollContent(
        contentWidth: CGFloat,
        pageInset: CGFloat,
        availableHeight: CGFloat,
        layout: HomeLayoutProfile
    ) -> some View {
        let dealBannerHeight = HomeMetrics.dealBannerHeight(for: contentWidth)
        let favoriteCardWidth = HomeMetrics.freshFavoriteCardWidth(for: contentWidth)

        return VStack(alignment: .leading, spacing: 0) {
            SnowfallTitleContainer(
                cornerRadius: 30,
                horizontalPadding: TBTheme.spacingLG + 2,
                verticalPadding: HomeMetrics.logoSnowfallVerticalPadding,
                flakeCount: 84
            ) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: layout.logoImageHeight)
                    .scaleEffect(HomeMetrics.logoVisualScale)
                    .offset(y: layout.logoTopOffset)
            }
            .frame(maxWidth: .infinity)

            if let dealOfDayProduct = featuredProduct {
                Color.clear
                    .frame(height: layout.logoToDealSpacing)

                DealOfDayBanner(product: dealOfDayProduct)
                    .environment(\.dealBannerContentWidth, contentWidth)
                    .frame(height: dealBannerHeight)

                Color.clear
                    .frame(height: layout.dealToFavoritesSpacing)
            }

            freshFavoritesSection(cardWidth: favoriteCardWidth, pageInset: pageInset, layout: layout)

            Color.clear
                .frame(height: layout.favoritesToSpotlightSpacing)

            Group {
                if let featuredCreator {
                    makerSpotlightSection(featuredCreator, layout: layout)
                } else {
                    Color.clear
                        .frame(height: layout.spotlightBlockMinHeight)
                        .accessibilityHidden(true)
                }
            }

            Color.clear
                .frame(height: layout.spotlightToTabSpacing)
        }
        .frame(maxWidth: .infinity, minHeight: availableHeight, alignment: .topLeading)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let pageInset = HomeMetrics.pageInset
                let contentWidth = max(geometry.size.width - (pageInset * 2), 0)
                let layout = HomeLayoutProfile.resolved(for: geometry.size.height)
                let bottomClearance = HomeMetrics.tabBarScrollClearance + layout.bottomClearanceExtra
                let availableHeight = max(
                    geometry.size.height - TopLevelHeaderMetrics.homeTopInset - bottomClearance,
                    0
                )

                homeScrollContent(
                    contentWidth: contentWidth,
                    pageInset: pageInset,
                    availableHeight: availableHeight,
                    layout: layout
                )
                    .padding(.horizontal, pageInset)
                    .padding(.top, TopLevelHeaderMetrics.homeTopInset)
                    .padding(.bottom, bottomClearance)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .clipped()
                .background(TBFrostBackground())
            }
            .task {
                await refreshLiveDropIfNeeded()
            }
            .task(id: featuredProductsTaskKey) {
                refreshFeaturedProductsCache()
            }
            .onAppear {
                isHomeVisible = true
                seedRotations()
            }
            .onDisappear {
                isHomeVisible = false
            }
            .onReceive(rotationTimer) { _ in
                guard isHomeVisible else { return }
                advanceRotations()
            }
            .navigationBarTitleDisplayMode(.inline)
            #if os(iOS) || os(visionOS)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Occupies the nav bar title slot without drawable text. Zero‑width / empty titles can render as
                    // stray punctuation on hardware (the marks users saw under the Dynamic Island).
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 2) {
                        NavigationLink {
                            profileDestination
                        } label: {
                            profileToolbarIcon
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(userRole == "seller" ? "Open seller profile" : "Open buyer profile")

                        NavigationLink {
                            NotificationsHubView()
                        } label: {
                            NotificationBellButton(unreadCount: notifications.unreadCount())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    CartButton(itemCount: cart.items.reduce(0) { $0 + $1.quantity }) {
                        showCart = true
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            #else
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 2) {
                        NavigationLink {
                            profileDestination
                        } label: {
                            profileToolbarIcon
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(userRole == "seller" ? "Open seller profile" : "Open buyer profile")

                        NavigationLink {
                            NotificationsHubView()
                        } label: {
                            NotificationBellButton(unreadCount: notifications.unreadCount())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .automatic) {
                    CartButton(itemCount: cart.items.reduce(0) { $0 + $1.quantity }) {
                        showCart = true
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            #endif
            .sheet(isPresented: $showCart) {
                CartView()
                    .environmentObject(cart)
                    .environmentObject(catalog)
                    .environmentObject(localProducts)
            }
            .navigationDestination(item: $selectedFeaturedCreator) { seller in
                PublicSellerProfileView(
                    seller: seller,
                    products: products(for: seller)
                )
            }
        }
    }

    private func refreshLiveDropIfNeeded(force: Bool = false) async {
        let now = Date()
        guard !isLiveDropRefreshInFlight else { return }
        guard force || now.timeIntervalSince(lastLiveDropRefresh) > 45 else { return }
        isLiveDropRefreshInFlight = true
        defer { isLiveDropRefreshInFlight = false }
        lastLiveDropRefresh = now

        do {
            liveDrop = try await DropAPI.currentDrop()
        } catch {
            // Keep the existing/fallback drop content during transient network failures.
        }
    }
}

private struct DealBannerContentWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 361
}

private extension EnvironmentValues {
    var dealBannerContentWidth: CGFloat {
        get { self[DealBannerContentWidthKey.self] }
        set { self[DealBannerContentWidthKey.self] = newValue }
    }
}

private struct DealOfDayBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dealBannerContentWidth) private var bannerContentWidth
    let product: Product

    /// Matches the “Deal of the Day” label capsule so the CTA does not read larger.
    private enum DealCapsuleMetrics {
        static let font = Font.system(size: 11, weight: .bold, design: .rounded)
        static let horizontalPadding: CGFloat = 9
        static let verticalPadding: CGFloat = 4
    }

    private var artworkContainerSize: CGFloat {
        min(max(bannerContentWidth * 0.242, 84), 96)
    }

    private var artworkImageSize: CGFloat {
        artworkContainerSize
    }

    private var artworkCornerRadius: CGFloat {
        20
    }

    private var horizontalPadding: CGFloat {
        min(max(bannerContentWidth * 0.045, 14), 18)
    }

    private var bannerSpacing: CGFloat {
        bannerContentWidth < 370 ? TBTheme.spacingMD : TBTheme.spacingLG
    }

    var body: some View {
        HStack(alignment: .top, spacing: bannerSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Deal of the Day")
                    .font(DealCapsuleMetrics.font)
                    .textCase(.uppercase)
                    .tracking(0.45)
                    .foregroundStyle(.white.opacity(0.96))
                    .padding(.horizontal, DealCapsuleMetrics.horizontalPadding)
                    .padding(.vertical, DealCapsuleMetrics.verticalPadding)
                    .background(Color.white.opacity(0.22))
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.18), lineWidth: 0.8)
                    )
                    .clipShape(Capsule())

                Text(product.name)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(-0.35)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.leading)
                    .shadow(color: TBTheme.bannerCTAForeground.opacity(0.18), radius: 1.5, y: 1)

                Text(Money.format(cents: product.priceCents))
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                    .tracking(-0.45)
                    .foregroundStyle(.white)
                    .shadow(color: TBTheme.bannerCTAForeground.opacity(0.16), radius: 1.5, y: 1)

                actionStack
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.16),
                                .white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    )
                    .frame(width: artworkContainerSize, height: artworkContainerSize)

                StorefrontImageView(reference: product.primaryImageReference, contentMode: .fill) {
                    Image(systemName: product.category.icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(width: artworkImageSize, height: artworkImageSize)
                }
                .frame(width: artworkImageSize, height: artworkImageSize)
                .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
                )
            }
            .frame(width: artworkContainerSize, height: artworkContainerSize)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, TBTheme.spacingSM + 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.35, green: 0.58, blue: 0.91),
                        Color(red: 0.28, green: 0.54, blue: 0.92),
                        Color(red: 0.24, green: 0.49, blue: 0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                SnowfallParticleCanvas(flakeCount: 84)
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.18),
                            .white.opacity(0.06),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG, style: .continuous)
                .strokeBorder(TBTheme.frostEdgeOnDark, lineWidth: 1.1)
                .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: TBTheme.radiusLG, style: .continuous))
        .shadow(color: TBTheme.deepSky.opacity(0.16), radius: 10, y: 4)
    }

    @ViewBuilder
    private var actionStack: some View {
        detailsButton
    }

    private var detailsButton: some View {
        NavigationLink {
            ProductDetailView(product: product)
        } label: {
            HStack(spacing: 5) {
                Text("View details")
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .font(DealCapsuleMetrics.font)
            .tracking(-0.04)
            .foregroundStyle(TBTheme.bannerCTAForeground)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, DealCapsuleMetrics.horizontalPadding)
            .padding(.vertical, DealCapsuleMetrics.verticalPadding)
            .background(.ultraThinMaterial, in: Capsule())
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.20),
                                .white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.32), lineWidth: 0.9)
            )
            .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View details for \(product.name)")
    }
}

private struct CreatorSpotlightCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let creator: SellerProfile
    let onOpenStore: () -> Void

    private var isAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private let cardCornerRadius: CGFloat = 20

    var body: some View {
        Group {
            if isAccessibilityLayout {
                VStack(alignment: .leading, spacing: 12) {
                    creatorIdentity
                    footer
                }
            } else {
                HStack(spacing: 12) {
                    creatorIdentity
                    .frame(maxWidth: .infinity, alignment: .leading)
                    footer
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isAccessibilityLayout ? 14 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.95), TBTheme.skyBlue.opacity(0.34)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .shadow(color: TBTheme.deepSky.opacity(0.15), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    .white.opacity(0.90),
                    TBTheme.skyLight.opacity(0.54),
                    TBTheme.skyBlue.opacity(0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(TBTheme.skyBlue.opacity(0.18))
                .frame(width: 110, height: 110)
                .blur(radius: 24)
                .offset(x: 170, y: 25)
        }
    }

    private var creatorIdentity: some View {
        HStack(alignment: .center, spacing: 10) {
            spotlightAvatar

            VStack(alignment: .leading, spacing: 2) {
                Text("FEATURED MAKER")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(TBTheme.icyBlue)

                HStack(spacing: 5) {
                    Text(creator.displayName)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(TBTheme.deepSky)
                        .lineLimit(1)

                    if creator.showsVerifiedBadge {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TBTheme.skyBlue)
                            .accessibilityLabel("Verified seller")
                    }
                }

                Text(creator.handle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TBTheme.icyBlue)
                    .lineLimit(1)
            }
        }
    }

    private var spotlightAvatar: some View {
        StorefrontImageView(reference: creator.avatarMediaReference, contentMode: .fill) {
            ZStack {
                LinearGradient(
                    colors: [.white, TBTheme.skyLight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky.opacity(0.68))
            }
        }
        .frame(width: 50, height: 50)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(.white.opacity(0.96), lineWidth: 2)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.12), radius: 6, y: 3)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if isAccessibilityLayout {
                Label("\(creator.productCount) products", systemImage: "cube.fill")
                Label("\(creator.likeCount) likes", systemImage: "heart.fill")
            }
            storeButton
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(TBTheme.deepSky.opacity(0.76))
    }

    private var storeButton: some View {
        Button(action: onOpenStore) {
            HStack(spacing: 4) {
                Text("Store")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(minHeight: 44)
            .background(TBTheme.deepSky, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.34), lineWidth: 1)
            )
            .shadow(color: TBTheme.deepSky.opacity(0.18), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View \(creator.displayName) store")
    }
}

// MARK: - Memoized home catalog snapshot

/// Reference-type box stored in `@State`; mutating its contents during body evaluation is
/// allowed and doesn't trigger extra renders, which makes it a safe memoization slot.
private final class HomeCatalogCache {
    var snapshot: HomeCatalogSnapshot?
}

/// Immutable per-revision snapshot of the resolved catalog. Profile dictionaries are derived
/// lazily because most renders never touch every section.
private final class HomeCatalogSnapshot {
    let key: String
    let products: [Product]
    let freshFavoritesCatalog: [Product]

    private let remoteProfiles: [SellerProfile]
    private var cachedSellerProfilesByID: [String: SellerProfile]?
    private var cachedFreshFavoritesSellerProfilesByID: [String: SellerProfile]?

    init(
        key: String,
        products: [Product],
        freshFavoritesCatalog: [Product],
        remoteProfiles: [SellerProfile]
    ) {
        self.key = key
        self.products = products
        self.freshFavoritesCatalog = freshFavoritesCatalog
        self.remoteProfiles = remoteProfiles
    }

    var sellerProfilesByID: [String: SellerProfile] {
        if let cached = cachedSellerProfilesByID { return cached }
        let resolved = resolvedSellerProfilesByID(
            storefrontProducts: products,
            remoteProfiles: remoteProfiles
        )
        cachedSellerProfilesByID = resolved
        return resolved
    }

    var freshFavoritesSellerProfilesByID: [String: SellerProfile] {
        if let cached = cachedFreshFavoritesSellerProfilesByID { return cached }
        let resolved = resolvedSellerProfilesByID(
            storefrontProducts: freshFavoritesCatalog,
            remoteProfiles: remoteProfiles
        )
        cachedFreshFavoritesSellerProfilesByID = resolved
        return resolved
    }
}



