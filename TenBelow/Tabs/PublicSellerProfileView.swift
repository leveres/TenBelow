import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PublicSellerProfileView: View {
    let seller: SellerProfile
    let products: [Product]
    var previewDraftIDs: Set<String> = []
    var avatarNamespace: Namespace.ID? = nil

    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore
    @EnvironmentObject private var orderStore: OrderStore
    @EnvironmentObject private var inquiryStore: SellerInquiryStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @Environment(\.openURL) private var openURL
    @AppStorage("buyerAccountCreated") private var buyerAccountCreated = false
    @State private var currentProductPage = 0
    @State private var selectedProduct: Product?
    @State private var showMessagingGate = false
    @State private var activeShopChat: ShopChatSheetItem?
    @State private var pendingExternalWebsiteURL: URL?
    #if os(iOS)
    @State private var showShareSheet = false
    @State private var showCustomOrderSheet = false
    #endif
    @State private var profileCache = ProfileCache()

    private let productsPerPage = 4

    /// Body reads `resolvedSeller` / `sellerProducts` many times per render, and each
    /// uncached resolution re-merges the catalog and re-sorts. Memoized per revision so a
    /// push renders with one resolution pass.
    private final class ProfileCache {
        var key: String?
        var sellerProducts: [Product] = []
        var resolvedSeller: SellerProfile?
    }

    private var profileSnapshotKey: String {
        "\(catalog.contentRevision)|\(localProducts.productsRevision)|\(seller.id)"
    }

    private var brandTheme: StorefrontBrandTheme {
        StorefrontBrandTheme.theme(for: resolvedSeller.id)
    }

    private var sellerProducts: [Product] {
        refreshProfileCacheIfNeeded()
        return profileCache.sellerProducts
    }

    private var resolvedSeller: SellerProfile {
        refreshProfileCacheIfNeeded()
        return profileCache.resolvedSeller ?? seller
    }

    private func refreshProfileCacheIfNeeded() {
        let key = profileSnapshotKey
        guard profileCache.key != key else { return }

        let fromPassedCatalog = products.filter { $0.sellerId == seller.id }
        let base: [Product]
        if !fromPassedCatalog.isEmpty {
            base = fromPassedCatalog
        } else {
            let storefrontProducts = resolvedStorefrontProducts(
                remoteProducts: catalog.products,
                fallbackProducts: localProducts.products
            )
            base = storefrontProducts.filter { $0.sellerId == seller.id }
        }

        let sorted = base.sorted { lhs, rhs in
            let lhsIsPreview = previewDraftIDs.contains(lhs.id)
            let rhsIsPreview = previewDraftIDs.contains(rhs.id)
            if lhsIsPreview != rhsIsPreview {
                return lhsIsPreview && !rhsIsPreview
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let resolved = resolvedSellerProfile(
            sellerId: seller.id,
            storefrontProducts: sorted,
            remoteProfiles: catalog.sellerProfiles
        )

        profileCache.key = key
        profileCache.sellerProducts = sorted
        profileCache.resolvedSeller = resolved?.mergingFallback(seller) ?? seller
    }

    private var totalProductPages: Int {
        max(1, Int(ceil(Double(sellerProducts.count) / Double(productsPerPage))))
    }

    private var currentPageProducts: [Product] {
        guard !sellerProducts.isEmpty else { return [] }
        let safePage = min(currentProductPage, totalProductPages - 1)
        let startIndex = safePage * productsPerPage
        let endIndex = min(startIndex + productsPerPage, sellerProducts.count)
        guard startIndex < endIndex else { return [] }
        return Array(sellerProducts[startIndex..<endIndex])
    }

    private var isSellerFollowed: Bool {
        buyerEngagement.isSellerFollowed(seller.id)
    }

    var body: some View {
        loadedContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.96, green: 0.98, blue: 1.0).ignoresSafeArea())
        .navigationTitle("")
        #if os(iOS) || os(visionOS)
        // When opened from Shop (hidden root bar), ensure standard navigation chrome returns.
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $showMessagingGate) {
            OrderMessagingGateSheet(sellerName: resolvedSeller.displayName)
        }
        .sheet(item: $activeShopChat) { chat in
            OrderSupportThreadView(
                sellerId: chat.sellerId,
                sellerName: chat.sellerName,
                viewerRole: .buyer
            )
            .environmentObject(orderStore)
            .environmentObject(inquiryStore)
        }
        #if os(iOS)
        .sheet(isPresented: $showShareSheet) {
            ActivityView(items: [sellerShareText])
        }
        .sheet(isPresented: $showCustomOrderSheet) {
            BuyerCustomOrderRequestSheet(seller: resolvedSeller)
        }
        #endif
        .onChange(of: sellerProducts.count) { _, _ in
            currentProductPage = min(currentProductPage, max(totalProductPages - 1, 0))
        }
        .navigationDestination(item: $selectedProduct) { product in
            ProductDetailView(product: product)
        }
        .confirmationDialog(
            "Open seller website?",
            isPresented: Binding(
                get: { pendingExternalWebsiteURL != nil },
                set: { shouldShow in
                    if !shouldShow {
                        pendingExternalWebsiteURL = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Open in Safari") {
                guard let pendingExternalWebsiteURL else { return }
                openURL(pendingExternalWebsiteURL)
                self.pendingExternalWebsiteURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingExternalWebsiteURL = nil
            }
        } message: {
            Text("You're leaving TenBelow to visit a seller-managed website in Safari.")
        }
    }

    // MARK: - Banner Header

    private var bannerHeader: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.52),
                ],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: TBTheme.spacingLG) {
                profileAvatar
                    .offset(y: 10)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(resolvedSeller.displayName)
                            .font(.tbCardTitle)
                            .foregroundStyle(Color.white.opacity(0.96))

                        if resolvedSeller.showsVerifiedBadge {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.84))
                        }
                    }

                    Text(resolvedSeller.handle)
                        .font(.tbBody)
                        .foregroundStyle(Color.white.opacity(0.72))

                    HStack(spacing: 10) {
                        Text("\(sellerProducts.count) products")
                            .font(.tbMeta)
                            .foregroundStyle(Color.white.opacity(0.74))

                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text(formattedLikes)
                                .font(.tbMeta)
                        }
                        .foregroundStyle(Color.white.opacity(0.78))
                    }
                }

                Spacer()
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.bottom, 8)
        }
        .frame(height: 118)
        .background {
            bannerBackground
                .ignoresSafeArea(edges: .top)
        }
        .padding(.bottom, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(resolvedSeller.displayName), \(resolvedSeller.handle), \(sellerProducts.count) products, \(formattedLikes) likes")
    }

    private var bannerBackground: some View {
        StorefrontImageView(reference: resolvedSeller.bannerURL?.absoluteString, contentMode: .fill) {
            LinearGradient(
                colors: brandTheme.bannerGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let avatarNamespace {
            avatarView
                .matchedGeometryEffect(id: "sellerAvatar", in: avatarNamespace)
        } else {
            avatarView
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 50, height: 50)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [brandTheme.accent, brandTheme.accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: brandTheme.accent.opacity(0.2), radius: 10, y: 4)

            StorefrontImageView(reference: resolvedSeller.avatarURL?.absoluteString, contentMode: .fill) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white, Color(red: 0.90, green: 0.95, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Text(avatarInitials)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.24, green: 0.47, blue: 0.78))
                    }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.04), lineWidth: 0.8)
            )
        }
        .accessibilityHidden(true)
    }

    private var avatarInitials: String {
        let words = resolvedSeller.displayName.split(separator: " ")
        let initials = words.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.joined()
    }

    // MARK: - Badges (compact pills)

    private var badgeRow: some View {
        FlowLayout(spacing: 6) {
            SellerBadge(
                text: resolvedSeller.designLicense,
                icon: "doc.text.fill",
                tint: Color(red: 0.39, green: 0.59, blue: 0.87),
                isCompact: true
            )
            SellerBadge(
                text: "Ships in \(resolvedSeller.shipsInDays.lowerBound)–\(resolvedSeller.shipsInDays.upperBound) days",
                icon: "shippingbox",
                isCompact: true
            )
            SellerBadge(
                text: resolvedSeller.location,
                icon: "location.fill",
                isCompact: true
            )
            if resolvedSeller.showsVerifiedBadge {
                SellerBadge(
                    text: "Verified",
                    icon: "checkmark.seal.fill",
                    tint: Color(red: 0.26, green: 0.68, blue: 0.49),
                    isCompact: true
                )
            }
        }
    }

    // MARK: - Products Section

    private var productsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Products")
                    .font(.tbHeadline)
                    .foregroundStyle(.primary.opacity(0.88))

                Spacer()

                if !sellerProducts.isEmpty {
                    Text("Page \(min(currentProductPage + 1, totalProductPages)) of \(totalProductPages)")
                        .font(.tbMeta)
                        .foregroundStyle(.secondary)
                }
            }

            if sellerProducts.isEmpty {
                emptyProductsState
                    .padding(.vertical, TBTheme.spacingMD)
            } else {
                GeometryReader { geo in
                    let gridColumnSpacing: CGFloat = 10
                    let gridRowSpacing: CGFloat = 8
                    let sectionStackSpacing: CGFloat = totalProductPages > 1 ? 8 : 0
                    let tileWidth = max((geo.size.width - gridColumnSpacing) / 2, 0)
                    let artworkHeight = min(max(tileWidth * 0.58, 82), 104)
                    let rowCellHeight = artworkHeight + 66

                    VStack(spacing: sectionStackSpacing) {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: gridColumnSpacing, alignment: .top),
                                GridItem(.flexible(), spacing: gridColumnSpacing, alignment: .top)
                            ],
                            spacing: gridRowSpacing
                        ) {
                            ForEach(currentPageProducts) { product in
                                SellerProfileProductTile(
                                    product: product,
                                    isDraftPreview: previewDraftIDs.contains(product.id),
                                    rowHeight: rowCellHeight,
                                    artworkHeight: artworkHeight,
                                    onSelect: { selectedProduct = product }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)

                        if totalProductPages > 1 {
                            HStack(spacing: 10) {
                                Button {
                                    currentProductPage = max(currentProductPage - 1, 0)
                                } label: {
                                    paginationArrow(systemName: "chevron.left")
                                }
                                .disabled(currentProductPage == 0)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(0..<totalProductPages, id: \.self) { page in
                                            Button {
                                                currentProductPage = page
                                            } label: {
                                                Text("\(page + 1)")
                                                    .font(.tbMeta)
                                                    .foregroundStyle(page == currentProductPage ? .white : .primary.opacity(0.72))
                                                    .frame(width: 30, height: 30)
                                                    .background(
                                                        Group {
                                                            if page == currentProductPage {
                                                                Circle()
                                                                    .fill(TBTheme.deepSky.opacity(0.9))
                                                            } else {
                                                                Circle()
                                                                    .fill(.white.opacity(0.92))
                                                                    .overlay(
                                                                        Circle()
                                                                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                                                                    )
                                                            }
                                                        }
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                }

                                Button {
                                    currentProductPage = min(currentProductPage + 1, totalProductPages - 1)
                                } label: {
                                    paginationArrow(systemName: "chevron.right")
                                }
                                .disabled(currentProductPage >= totalProductPages - 1)
                            }
                        }
                    }
                }
                .frame(height: gridSectionHeight(for: currentPageProducts.count))
                .animation(.easeInOut(duration: 0.2), value: currentProductPage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func gridSectionHeight(for productCount: Int) -> CGFloat {
        let rowCount = max(1, Int(ceil(Double(productCount) / 2.0)))
        let rowHeight: CGFloat = 170
        let rowSpacing: CGFloat = 8
        let paginationHeight: CGFloat = totalProductPages > 1 ? 40 : 0
        let stackSpacing: CGFloat = totalProductPages > 1 ? 8 : 0
        return (CGFloat(rowCount) * rowHeight)
            + (CGFloat(max(0, rowCount - 1)) * rowSpacing)
            + paginationHeight
            + stackSpacing
    }

    private func paginationArrow(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.75))
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(.white.opacity(0.92))
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
            )
    }

    private var emptyProductsState: some View {
        GlassCard {
            VStack(spacing: TBTheme.spacingSM) {
                Image(systemName: "cube")
                    .font(.system(size: 24))
                    .foregroundStyle(TBTheme.skyBlue.opacity(0.5))

                Text("No products yet")
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)

                Text("This seller hasn't listed any live products yet. Check back soon for new items.")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TBTheme.spacingLG)
        }
    }

    // MARK: - About Section (compact)

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(resolvedSeller.bio)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let url = resolvedSeller.websiteURL {
                Button {
                    pendingExternalWebsiteURL = url
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .medium))
                        Text(url.absoluteString)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionSection: some View {
        ViewThatFits(in: .horizontal) {
            actionButtonRow(showIcons: true)
            actionButtonRow(showIcons: false)
        }
        .zIndex(1)
    }

    private func actionButtonRow(showIcons: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                _ = buyerEngagement.toggleFollow(sellerId: seller.id)
            } label: {
                actionPillLabel(
                    title: isSellerFollowed ? "Following" : "Follow",
                    systemImage: isSellerFollowed ? "checkmark.circle.fill" : "plus.circle.fill",
                    showIcon: showIcons,
                    isSelected: isSellerFollowed
                )
            }
            .buttonStyle(.plain)

            Button {
                openSellerMessaging()
            } label: {
                actionPillLabel(
                    title: "Message",
                    systemImage: "bubble.left.and.bubble.right.fill",
                    showIcon: showIcons
                )
            }
            .buttonStyle(.plain)

            #if os(iOS)
            if resolvedSeller.acceptsCustomOrders {
                Button {
                    showCustomOrderSheet = true
                } label: {
                    actionPillLabel(
                        title: "Custom",
                        systemImage: "pencil.and.outline",
                        showIcon: showIcons
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Request custom")
            }
            #endif

            #if os(iOS)
            Button {
                showShareSheet = true
            } label: {
                actionPillLabel(
                    title: "Share",
                    systemImage: "square.and.arrow.up",
                    showIcon: showIcons
                )
            }
            .buttonStyle(.plain)
            #else
            ShareLink(item: sellerShareText, subject: Text(resolvedSeller.displayName), message: Text(sellerShareText)) {
                actionPillLabel(
                    title: "Share",
                    systemImage: "square.and.arrow.up",
                    showIcon: showIcons
                )
            }
            .buttonStyle(.plain)
            #endif
        }
    }

    private func actionPillLabel(
        title: String,
        systemImage: String,
        showIcon: Bool,
        isSelected: Bool = false
    ) -> some View {
        Group {
            if showIcon {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
            } else {
                Text(title)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(isSelected ? TBTheme.deepSky : TBTheme.bannerCTAForeground)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            ZStack {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(isSelected ? 0.34 : 0.28),
                                .white.opacity(isSelected ? 0.14 : 0.10),
                                TBTheme.skyBlue.opacity(isSelected ? 0.12 : 0.08),
                                .white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.42), .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.55)
                        )
                    )
            }
        }
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.95),
                            TBTheme.skyBlue.opacity(isSelected ? 0.68 : 0.55),
                            TBTheme.deepSky.opacity(isSelected ? 0.38 : 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: TBTheme.deepSky.opacity(0.10), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        .shadow(color: .white.opacity(0.45), radius: 1, y: -1)
        .contentShape(Capsule(style: .continuous))
    }

    private var sellerShareText: String {
        if let website = resolvedSeller.websiteURL?.absoluteString {
            return "\(resolvedSeller.displayName) on TenBelow\n\(website)"
        }

        return "\(resolvedSeller.displayName) on TenBelow\n\(resolvedSeller.handle)"
    }

    private func openSellerMessaging() {
        guard buyerAccountCreated else {
            showMessagingGate = true
            return
        }

        activeShopChat = ShopChatSheetItem(
            sellerId: resolvedSeller.id,
            sellerName: resolvedSeller.displayName
        )
        Task {
            await inquiryStore.refreshBuyerThreads()
        }
    }

    private var formattedLikes: String {
        let count = resolvedSeller.likeCount
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    // MARK: - Content

    private var loadedContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                bannerHeader

                VStack(spacing: 8) {
                    badgeRow
                        .frame(maxWidth: .infinity, alignment: .leading)

                    aboutCard

                    actionSection

                    productsSection
                        .padding(.top, 4)
                }
                .padding(.horizontal, TBTheme.spacingLG)
                .padding(.bottom, 24)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private enum SellerStoreDraftPreviewStorage {
    static func key(for sellerId: String) -> String {
        "sellerProductDraftsData.\(sellerId)"
    }
}

// MARK: - About Badge Pill (reference-style: icon + title + chevron)

private struct AboutBadgePill: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let icon: String
    let title: String
    var tint: Color = TBTheme.icyBlue

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Seller Profile Product Tile

private struct SellerProfileProductTile: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let product: Product
    var isDraftPreview: Bool = false
    /// When set, tile fills a grid row of this height (public profile stretch layout).
    var rowHeight: CGFloat?
    var artworkHeight: CGFloat = 62
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    productArtwork
                        .frame(maxWidth: .infinity)
                        .frame(height: artworkHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    if isDraftPreview {
                        Text("Preview")
                            .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 12 : 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(TBTheme.deepSky)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.92), in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(TBTheme.skyBlue.opacity(0.18), lineWidth: 0.8)
                            )
                            .padding(8)
                    }
                }

                Text(product.name)
                    .font(.tbProductTitleSM)
                    .tbProductNameTitleStyle()
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .center) {
                    Text(Money.format(cents: product.priceCents))
                        .font(.tbProductPriceSM)
                        .foregroundStyle(.primary.opacity(0.82))

                    Spacer(minLength: 6)

                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(product.category.rawValue)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.78))
                            .lineLimit(1)
                    }
                }
            }
            .padding(8)
            .frame(
                maxWidth: .infinity,
                minHeight: rowHeight ?? (dynamicTypeSize.isAccessibilitySize ? 118 : 102),
                maxHeight: rowHeight,
                alignment: .topLeading
            )
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.99), Color(red: 0.972, green: 0.985, blue: 1.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.black.opacity(0.045), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.035), radius: 10, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tileAccessibilityLabel)
        .accessibilityHint("Opens product details.")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var productArtwork: some View {
        if product.primaryImageReference != nil {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: categoryArtworkColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                StorefrontImageView(reference: product.primaryImageReference) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .overlay {
                            Image(systemName: product.category.icon)
                                .foregroundStyle(.white.opacity(0.82))
                        }
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.22), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)

                VStack {
                    HStack {
                        if !dynamicTypeSize.isAccessibilitySize {
                            categoryPill
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(6)
            }
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: categoryArtworkColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 5) {
                            Image(systemName: product.category.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(categoryAccent.opacity(0.80))

                            Text(product.material)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }

                        VStack {
                            HStack {
                                if !dynamicTypeSize.isAccessibilitySize {
                                    categoryPill
                                }
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(6)
                    }
                }
        }
    }

    private var categoryPill: some View {
        HStack(spacing: 4) {
            Image(systemName: product.category.icon)
                .font(.caption2.weight(.semibold))
            Text(product.category.rawValue)
                .font(.caption2.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(categoryAccent)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.white.opacity(0.92), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.black.opacity(0.04), lineWidth: 0.8)
        )
    }

    private var categoryAccent: Color {
        switch product.category {
        case .home:
            return Color(red: 0.40, green: 0.63, blue: 0.94)
        case .desk:
            return Color(red: 0.29, green: 0.56, blue: 0.90)
        case .car:
            return Color(red: 0.33, green: 0.62, blue: 0.86)
        case .tech:
            return Color(red: 0.37, green: 0.53, blue: 0.93)
        case .gifts:
            return Color(red: 0.54, green: 0.58, blue: 0.95)
        case .didntKnow:
            return Color(red: 0.46, green: 0.60, blue: 0.94)
        }
    }

    private var categoryArtworkColors: [Color] {
        switch product.category {
        case .home:
            return [Color(red: 0.95, green: 0.98, blue: 1.0), .white]
        case .desk:
            return [Color(red: 0.94, green: 0.975, blue: 1.0), .white]
        case .car:
            return [Color(red: 0.95, green: 0.98, blue: 0.995), .white]
        case .tech:
            return [Color(red: 0.945, green: 0.97, blue: 1.0), .white]
        case .gifts:
            return [Color(red: 0.97, green: 0.965, blue: 1.0), .white]
        case .didntKnow:
            return [Color(red: 0.955, green: 0.975, blue: 1.0), .white]
        }
    }

    private var tileAccessibilityLabel: String {
        var parts = [product.name, Money.format(cents: product.priceCents), product.category.rawValue]
        if isDraftPreview {
            parts.append("Preview")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Seller All Products (full grid via See All)

private struct SellerAllProductsView: View {
    let seller: SellerProfile
    let products: [Product]

    private let gridColumns = [
        GridItem(.flexible(), spacing: TBTheme.spacingMD),
        GridItem(.flexible(), spacing: TBTheme.spacingMD)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: TBTheme.spacingMD) {
                ForEach(products) { product in
                    ProductCard(product: product)
                }
            }
            .padding()
        }
        .background(Color(red: 0.96, green: 0.98, blue: 1.0).ignoresSafeArea())
        .navigationTitle(seller.displayName)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Flow Layout (for material chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = CGPoint(
                x: bounds.minX + result.origins[index].x,
                y: bounds.minY + result.origins[index].y
            )
            subview.place(at: point, proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews)
        -> (size: CGSize, origins: [CGPoint])
    {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), origins)
    }
}

private struct ShopChatSheetItem: Identifiable, Hashable {
    let sellerId: String
    let sellerName: String

    var id: String { sellerId }
}

// MARK: - Preview


