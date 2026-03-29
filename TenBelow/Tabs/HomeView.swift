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
    @State private var selectedFeaturedProduct: Product?
    @State private var selectedFeaturedCreator: SellerProfile?
    @State private var featuredRotationIndex = 0
    @State private var creatorRotationIndex = 0
    private let drop = MockData.currentDrop
    private let rotationInterval: TimeInterval = 120
    private let rotationTimer = Timer.publish(every: 120, on: .main, in: .common).autoconnect()

    /// Shared horizontal inset and vertical rhythm for the home screen.
    private enum HomeMetrics {
        static let pageInset = TBTheme.spacingXL
        static let sectionSpacing = TBTheme.spacingMD
        static let titleToContent = TBTheme.spacingXS + 2
        static let logoImageHeight: CGFloat = 118
        static let dealBannerHeight: CGFloat = 148
        static let spotlightBottomInset: CGFloat = 2
        static let freshFavoritesGridColumns = [
            GridItem(.flexible(), spacing: TBTheme.spacingMD),
            GridItem(.flexible(), spacing: TBTheme.spacingMD),
        ]
    }

    private var products: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var sellerProfilesByID: [String: SellerProfile] {
        resolvedSellerProfilesByID(
            storefrontProducts: products,
            remoteProfiles: catalog.sellerProfiles
        )
    }

    private var orders: [Order] {
        orderStore.orders
    }

    private var currentSellerProfile: SellerProfile {
        resolvedSellerProfile(
            sellerId: sellerId,
            storefrontProducts: products,
            remoteProfiles: catalog.sellerProfiles
        ) ?? .previewProfile(sellerId: sellerId, businessName: sellerBusinessName)
    }

    @ViewBuilder
    private var profileDestination: some View {
        if userRole == "seller" {
            PublicSellerProfileView(
                seller: currentSellerProfile,
                products: products
            )
        } else {
            BuyerProfileView()
        }
    }

    private var hasLiveDrop: Bool {
        if let d = liveDrop, d.active, !d.products.isEmpty { return true }
        return false
    }

    private var profileToolbarIcon: some View {
        Group {
            if userRole == "buyer", buyerAccountCreated, !buyerInitials.isEmpty {
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

        if catalog.config.dropEnabled {
            return Set(drop.products.map(\.id))
        }

        return []
    }

    private var featuredProducts: [Product] {
        let nonDropProducts = products.filter { !excludedFeaturedProductIDs.contains($0.id) }
        let source = nonDropProducts.isEmpty ? products : nonDropProducts

        let sellerBuckets = Dictionary(grouping: source, by: \.sellerId)
            .mapValues { sellerProducts in
                sellerProducts.sorted { lhs, rhs in
                    let lhsScore = dealOfDayPriorityScore(lhs)
                    let rhsScore = dealOfDayPriorityScore(rhs)

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

        var workingBuckets = sellerBuckets
        var rotation: [Product] = []
        var appendedProductIDs = Set<String>()

        while rotation.count < source.count {
            var appendedInPass = false

            for sellerID in sellerOrder {
                guard var sellerProducts = workingBuckets[sellerID], !sellerProducts.isEmpty else { continue }
                let nextProduct = sellerProducts.removeFirst()
                workingBuckets[sellerID] = sellerProducts

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
        let nonDropProducts = products.filter { !excludedFeaturedProductIDs.contains($0.id) }
        let source = nonDropProducts.isEmpty ? products : nonDropProducts
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

        let ranked = rankingPool.sorted { lhs, rhs in
            let lhsScore = freshFavoritePriorityScore(lhs)
            let rhsScore = freshFavoritePriorityScore(rhs)

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

    private func dealOfDayPriorityScore(_ product: Product) -> Double {
        let salesCount = Double(productSalesCounts[product.id] ?? 0)
        let favorites = Double(product.favoriteCount)
        let productViews = Double(product.pageViewCount)
        let sellerTraffic = Double(sellerProfilesByID[product.sellerId]?.pageViewCount ?? 0)
        return salesCount * 45 + favorites * 8 + productViews * 0.35 + sellerTraffic * 0.05
    }

    private func freshFavoritePriorityScore(_ product: Product) -> Double {
        let salesCount = Double(productSalesCounts[product.id] ?? 0)
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

    var body: some View {
        NavigationStack {
            GeometryReader { _ in
                VStack(alignment: .leading, spacing: HomeMetrics.sectionSpacing) {
                    SnowfallTitleContainer(
                        cornerRadius: 30,
                        horizontalPadding: TBTheme.spacingLG + 2,
                        verticalPadding: TBTheme.spacingSM,
                        flakeCount: 84
                    ) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: HomeMetrics.logoImageHeight)
                    }
                    .frame(maxWidth: .infinity)

                    if let dealOfDayProduct = featuredProduct {
                        VStack(alignment: .leading, spacing: HomeMetrics.titleToContent) {
                            Text("Deal of the Day")
                                .font(.tbSectionTitle)
                                .tracking(-0.2)
                                .foregroundStyle(TBTheme.icyBlue)

                            DealOfDayBanner(product: dealOfDayProduct) {
                                selectedFeaturedProduct = dealOfDayProduct
                            }
                            .frame(height: HomeMetrics.dealBannerHeight)
                        }
                    }

                    VStack(alignment: .leading, spacing: HomeMetrics.titleToContent) {
                        Text("Fresh favorites")
                            .font(.tbSectionTitle)
                            .tracking(-0.2)
                            .foregroundStyle(TBTheme.icyBlue)

                        LazyVGrid(columns: HomeMetrics.freshFavoritesGridColumns, spacing: TBTheme.spacingMD) {
                            ForEach(freshFavoriteProducts.prefix(4)) { product in
                                ProductCard(
                                    product: product,
                                    seller: sellerProfilesByID[product.sellerId],
                                    allProducts: products,
                                    style: .blended
                                )
                            }
                        }
                    }

                    if let featuredCreator {
                        VStack(alignment: .leading, spacing: HomeMetrics.titleToContent) {
                            Text("Maker spotlight")
                                .font(.tbSectionTitle)
                                .tracking(-0.2)
                                .foregroundStyle(TBTheme.icyBlue)

                            CreatorSpotlightCard(
                                creator: featuredCreator,
                                onOpenStore: {
                                    selectedFeaturedCreator = featuredCreator
                                }
                            )
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                        .padding(.top, -10)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.bottom, HomeMetrics.spotlightBottomInset)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, HomeMetrics.pageInset)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .task {
                do { liveDrop = try await DropAPI.currentDrop() } catch { }
            }
            .onAppear {
                seedRotations()
            }
            .onReceive(rotationTimer) { _ in
                advanceRotations()
            }
            .background(TBTheme.cloudWhite)
            .navigationTitle("")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .navigationDestination(item: $selectedFeaturedProduct) { product in
                ProductDetailView(product: product)
            }
            .navigationDestination(item: $selectedFeaturedCreator) { seller in
                PublicSellerProfileView(
                    seller: seller,
                    products: products(for: seller)
                )
            }
        }
    }
}

private struct DealOfDayBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let product: Product
    let onSeeDetails: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: TBTheme.spacingLG) {
            VStack(alignment: .leading, spacing: TBTheme.spacingSM + 2) {
                Text(product.name)
                    .font(.tbProductTitleXL)
                    .tracking(-0.25)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.leading)

                Text(Money.format(cents: product.priceCents))
                    .font(.tbProductPriceLG)
                    .tracking(-0.5)
                    .foregroundStyle(.white)

                Spacer(minLength: TBTheme.spacingSM)

                actionStack
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

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
                    .frame(width: 96, height: 96)

                StorefrontImageView(reference: product.primaryImageReference, contentMode: .fit) {
                    Image(systemName: product.category.icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(width: 108, height: 108)
                }
                .frame(width: 108, height: 108)
                .shadow(color: .white.opacity(0.18), radius: 6, y: -1)
                .shadow(color: .black.opacity(0.10), radius: 10, y: 5)
                .offset(y: -2)
            }
            .frame(width: 104, height: 104)
        }
        .padding(.horizontal, TBTheme.spacingLG + 2)
        .padding(.vertical, TBTheme.spacingMD + 2)
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
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.9)
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
        Button(action: onSeeDetails) {
            HStack(spacing: 6) {
                Text("View details")
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
            }
            .font(.callout.weight(.semibold))
            .tracking(-0.08)
            .foregroundStyle(TBTheme.bannerCTAForeground)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.white.opacity(0.92)))
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.98), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct CreatorSpotlightCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let creator: SellerProfile
    let onOpenStore: () -> Void

    var body: some View {
        content
        .padding(.horizontal, TBTheme.spacingMD)
        .padding(.vertical, TBTheme.spacingMD + 2)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 108 : 88)
        .frame(maxWidth: .infinity, alignment: .center)
        .background {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.35, green: 0.58, blue: 0.91),
                        Color(red: 0.27, green: 0.52, blue: 0.90)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusXL, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.18),
                            .white.opacity(0.05),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusXL, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.9)
                .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: TBTheme.radiusXL, style: .continuous))
        .shadow(color: TBTheme.deepSky.opacity(0.07), radius: 6, y: 2)
    }

    private var avatarInitials: String {
        let words = creator.displayName.split(separator: " ")
        let initials = words.prefix(2).compactMap { $0.first }
        return initials.isEmpty ? "TB" : String(initials)
    }

    private var metadataText: String {
        "\(creator.productCount) products • \(formattedLikes)"
    }

    private var formattedLikes: String {
        let count = Double(creator.likeCount)

        guard count >= 1_000 else { return "\(creator.likeCount) likes" }

        let value = count / 1_000
        let text = value == floor(value)
            ? String(format: "%.0fk", value)
            : String(format: "%.1fk", value)

        return "\(text) likes"
    }

    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                headerRow
                storeButton
            }
        } else {
            HStack(alignment: .center, spacing: TBTheme.spacingMD) {
                headerRow
                    .frame(maxWidth: .infinity, alignment: .leading)
                storeButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: TBTheme.spacingMD) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.98), TBTheme.skyLight.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .strokeBorder(.white.opacity(0.88), lineWidth: 1)

                Text(avatarInitials)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: TBTheme.spacingXS) {
                Text(creator.displayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tracking(-0.15)
                    .foregroundStyle(.white)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                Text("Spotlight seller")
                    .font(.tbMicro)
                    .foregroundStyle(.white.opacity(0.82))

                Text(metadataText)
                    .font(.tbCaption)
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
        }
    }

    private var storeButton: some View {
        Button(action: onOpenStore) {
            HStack(spacing: TBTheme.spacingXS + 1) {
                Text("View store")
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(TBTheme.bannerCTAForeground)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, TBTheme.spacingMD)
            .padding(.vertical, TBTheme.spacingSM)
            .background(Capsule().fill(Color.white.opacity(0.92)))
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.98), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
    }
}

// MARK: - Live Drop Banner (replaces old DropHeroBanner on Home)

private struct LiveDropBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let endsAt: String
    let productCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("Weekend drop highlights")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack {
                Text(DropCountdown.timeLeft(until: endsAt))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.2))
                    .clipShape(Capsule())

                Spacer()

                viewDropPill
            }
        }
        .padding(TBTheme.spacingLG)
        .frame(height: 120)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TBTheme.dropBannerGradient)
        .cornerRadius(TBTheme.radiusLG)
        .shadow(color: TBTheme.skyBlue.opacity(0.25), radius: 10, y: 4)
    }

    private var viewDropPill: some View {
        HStack(spacing: 6) {
            Text("\(productCount) item\(productCount == 1 ? "" : "s")")
            Text("View drop")
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(TBTheme.bannerCTAForeground)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.92)))
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.98), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
    }
}

#Preview {
    let events = CommerceEventStore()
    let products = LocalProductStore(eventStore: events)
    let orders = OrderStore(eventStore: events)
    let engagement = BuyerEngagementStore(eventStore: events)
    let notifications = NotificationStore(
        eventStore: events,
        buyerEngagement: engagement,
        localProducts: products,
        orderStore: orders
    )

    return HomeView()
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
        .environmentObject(engagement)
        .environmentObject(products)
        .environmentObject(orders)
        .environmentObject(notifications)
}
