import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PublicSellerProfileView: View {
    let seller: SellerProfile
    let products: [Product]
    var previewDraftIDs: Set<String> = []
    var showsDraftPreviewBanner: Bool = false
    var avatarNamespace: Namespace.ID? = nil

    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore
    @EnvironmentObject private var buyerSellerThreads: BuyerSellerThreadStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @Environment(\.openURL) private var openURL
    @AppStorage("userRole") private var userRole = ""
    @State private var isLoading = true
    @State private var currentProductPage = 0
    @State private var messageThreadSeller: SellerProfile?
    #if os(iOS)
    @State private var showShareSheet = false
    #endif

    private let productsPerPage = 4

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var sellerProducts: [Product] {
        let fromPassedCatalog = products.filter { $0.sellerId == seller.id }
        let fromStorefrontCatalog = storefrontProducts.filter { $0.sellerId == seller.id }
        let base: [Product]
        if !fromPassedCatalog.isEmpty {
            base = fromPassedCatalog
        } else if !fromStorefrontCatalog.isEmpty {
            base = fromStorefrontCatalog
        } else {
            base = []
        }
        return base.sorted { lhs, rhs in
            let lhsIsPreview = previewDraftIDs.contains(lhs.id)
            let rhsIsPreview = previewDraftIDs.contains(rhs.id)
            if lhsIsPreview != rhsIsPreview {
                return lhsIsPreview && !rhsIsPreview
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var resolvedSeller: SellerProfile {
        resolvedSellerProfile(
            sellerId: seller.id,
            storefrontProducts: sellerProducts,
            remoteProfiles: catalog.sellerProfiles
        ) ?? seller
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
        ZStack {
            Group {
                if isLoading {
                    skeletonContent
                } else {
                    loadedContent
                }
            }

            if isLoading {
                AppLoadingOverlay(
                    title: "Loading Store",
                    subtitle: "Getting this seller's profile and products ready."
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.96, green: 0.98, blue: 1.0).ignoresSafeArea())
        .navigationTitle("")
        #if os(iOS) || os(visionOS)
        // When opened from Shop (hidden root bar), ensure standard navigation chrome returns.
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $messageThreadSeller) { profile in
            SellerMessagesView(seller: profile)
        }
        #if os(iOS)
        .sheet(isPresented: $showShareSheet) {
            ActivityView(items: [sellerShareText])
        }
        #endif
        .task {
            await reloadProfile()
        }
        .onChange(of: sellerProducts.count) { _, _ in
            currentProductPage = min(currentProductPage, max(totalProductPages - 1, 0))
        }
    }

    // MARK: - Banner Header

    private var bannerHeader: some View {
        ZStack(alignment: .bottom) {
            bannerGradient
                .frame(height: 90)
                .overlay(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.10),
                            .clear,
                            Color.black.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            HStack(alignment: .bottom, spacing: TBTheme.spacingLG) {
                profileAvatar
                    .offset(y: 14)

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
            .padding(.bottom, 10)
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(resolvedSeller.displayName), \(resolvedSeller.handle), \(sellerProducts.count) products, \(formattedLikes) likes")
    }

    private var bannerGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.30, green: 0.58, blue: 0.96),
                Color(red: 0.48, green: 0.72, blue: 0.98),
                Color(red: 0.83, green: 0.91, blue: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white, Color(red: 0.90, green: 0.95, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.04), lineWidth: 0.8)
                )

            Text(avatarInitials)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.24, green: 0.47, blue: 0.78))
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
                    let gridColumnSpacing: CGFloat = 12
                    let gridRowSpacing: CGFloat = 10
                    let sectionStackSpacing: CGFloat = 10
                    let paginationChromeHeight: CGFloat = 40
                    let gridBudget = max(
                        200,
                        geo.size.height - paginationChromeHeight - sectionStackSpacing
                    )

                    let rowCount = max(1, Int(ceil(Double(currentPageProducts.count) / 2.0)))
                    let totalRowSpacing = CGFloat(max(0, rowCount - 1)) * gridRowSpacing
                    let rawRowCellHeight = (gridBudget - totalRowSpacing) / CGFloat(rowCount)
                    let rowCellHeight = min(max(rawRowCellHeight, 188), 260)
                    let textAndChromeReserve: CGFloat = 54
                    let artworkHeight = min(max(104, rowCellHeight - textAndChromeReserve), 178)

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
                                    artworkHeight: artworkHeight
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(.easeInOut(duration: 0.2), value: currentProductPage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

                Text("Storefront updating")
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)

                Text("This seller does not have live products available right now. Check back soon.")
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
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let url = resolvedSeller.websiteURL {
                Button {
                    openURL(url)
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
        HStack(spacing: 8) {
            if userRole != "seller" {
                Button {
                    _ = buyerEngagement.toggleFollow(sellerId: seller.id)
                } label: {
                    Label(isSellerFollowed ? "Following" : "Follow", systemImage: isSellerFollowed ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(isSellerFollowed ? TBTheme.skyBlue : Color(red: 0.24, green: 0.47, blue: 0.78))
                .controlSize(.small)
                Button {
                    messageThreadSeller = resolvedSeller
                } label: {
                    Label("Message", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.24, green: 0.47, blue: 0.78))
                .controlSize(.small)
            }

            #if os(iOS)
            Button {
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            #else
            ShareLink(item: sellerShareText, subject: Text(resolvedSeller.displayName), message: Text(sellerShareText)) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            #endif
        }
    }

    private var sellerShareText: String {
        if let website = resolvedSeller.websiteURL?.absoluteString {
            return "\(resolvedSeller.displayName) on TenBelow\n\(website)"
        }

        return "\(resolvedSeller.displayName) on TenBelow\n\(resolvedSeller.handle)"
    }

    private var draftPreviewBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TBTheme.icyBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Previewing saved seller listings")
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)

                Text("Showing your saved draft products.")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 1)
        )
    }

    private var formattedLikes: String {
        let count = resolvedSeller.likeCount
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    // MARK: - Loading & Skeleton

    private var loadedContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                bannerHeader
                    .padding(.top, -16)

                VStack(spacing: 5) {
                    badgeRow
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if showsDraftPreviewBanner {
                        draftPreviewBanner
                    }

                    aboutCard

                    actionSection

                    productsSection
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, TBTheme.spacingLG)
                .padding(.top, 0)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom + 2, 4))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var skeletonContent: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(TBTheme.skyLight.opacity(0.6))
                .frame(height: 112)

            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .fill(TBTheme.skyLight.opacity(0.4))
                .frame(height: 28)
                .padding(.horizontal, TBTheme.spacingLG)
                .padding(.top, TBTheme.spacingMD)

            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .fill(TBTheme.skyLight.opacity(0.35))
                .frame(height: 52)
                .padding(.horizontal, TBTheme.spacingLG)
                .padding(.top, TBTheme.spacingMD)

            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .fill(TBTheme.skyLight.opacity(0.35))
                .frame(height: 44)
                .padding(.horizontal, TBTheme.spacingLG)
                .padding(.top, TBTheme.spacingMD)

            VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                RoundedRectangle(cornerRadius: TBTheme.radiusMD)
                    .fill(TBTheme.skyLight.opacity(0.35))
                    .frame(height: 16)

                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .fill(TBTheme.skyLight.opacity(0.35))
                    .frame(height: 200)
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.top, TBTheme.spacingLG)

            Spacer(minLength: 0)
        }
        .redacted(reason: .placeholder)
    }

    private func reloadProfile() async {
        await MainActor.run {
            isLoading = true
        }

        try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s shimmer-style pause

        await MainActor.run {
            isLoading = false
        }
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

// MARK: - Featured Product Card

private struct FeaturedProductCard: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
            Group {
                StorefrontImageView(reference: product.primaryImageReference) {
                    RoundedRectangle(cornerRadius: TBTheme.radiusMD)
                        .fill(Color.secondary.opacity(0.12))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 150, height: 120)
            .clipped()
            .cornerRadius(TBTheme.radiusMD)

            Text(product.name)
                .font(.tbProductTitleSM)
                .tbProductNameTitleStyle()
                .lineLimit(2)

            Text(Money.format(cents: product.priceCents))
                .font(.tbProductPriceSM)
                .foregroundStyle(.primary.opacity(0.82))
        }
        .frame(width: 150)
        .padding(TBTheme.spacingSM)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TBTheme.radiusLG))
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.04), radius: 6, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(product.name), \(Money.format(cents: product.priceCents)), featured product")
        .accessibilityHint("Opens product details.")
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

    var body: some View {
        NavigationLink {
            ProductDetailView(product: product)
        } label: {
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
            .padding(9)
            .frame(
                maxWidth: .infinity,
                minHeight: rowHeight ?? (dynamicTypeSize.isAccessibilitySize ? 118 : 102),
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tileAccessibilityLabel)
        .accessibilityHint("Opens product details.")
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

private struct SellerMessagesView: View {
    let seller: SellerProfile

    @EnvironmentObject private var threadStore: BuyerSellerThreadStore
    @State private var draftMessage = ""
    @State private var hasBootstrappedThread = false

    private var threadMessages: [BuyerSellerThreadMessage] {
        threadStore.messages(for: seller.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        messageHeaderCard

                        ForEach(threadMessages) { message in
                            SellerMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, TBTheme.spacingLG)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .onChange(of: threadMessages.count) { _, _ in
                    guard let last = threadMessages.last else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(red: 0.972, green: 0.981, blue: 0.993).ignoresSafeArea())
        .navigationTitle("Messages")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            messageComposer
        }
        .onAppear {
            guard !hasBootstrappedThread else { return }
            hasBootstrappedThread = true
            threadStore.bootstrapThreadIfNeeded(sellerId: seller.id, sellerDisplayName: seller.displayName)
        }
    }

    private var messageHeaderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message \(seller.displayName)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.88))

            Text("Ask about materials, shipping, or custom options.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                Text("Typical reply within a few hours")
                    .font(.caption)
            }
            .foregroundStyle(.secondary.opacity(0.9))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, y: 4)
    }

    private var messageComposer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Write a message...", text: $draftMessage, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.98), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                    )

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.36, green: 0.60, blue: 0.93),
                                    Color(red: 0.24, green: 0.47, blue: 0.78)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            }

            Text("Messages in this preview are saved on this device.")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, TBTheme.spacingLG)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(
            Color.white.opacity(0.92)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
        }
    }

    private func sendMessage() {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        threadStore.appendBuyerMessage(sellerId: seller.id, text: trimmed)
        draftMessage = ""
    }
}

private struct SellerMessageBubble: View {
    let message: BuyerSellerThreadMessage

    var body: some View {
        VStack(alignment: message.isFromBuyer ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.isFromBuyer { Spacer(minLength: 40) }

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.isFromBuyer ? .white : .primary.opacity(0.84))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(messageBubbleFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                message.isFromBuyer ? Color.clear : TBTheme.skyBlue.opacity(0.10),
                                lineWidth: 1
                            )
                    )

                if !message.isFromBuyer { Spacer(minLength: 40) }
            }

            Text(message.timestampLabel)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var messageBubbleFill: AnyShapeStyle {
        if message.isFromBuyer {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.36, green: 0.60, blue: 0.93),
                        Color(red: 0.24, green: 0.47, blue: 0.78)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    .white.opacity(0.98),
                    Color(red: 0.965, green: 0.982, blue: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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

// MARK: - Preview

#Preview("Public Profile") {
    let events = CommerceEventStore()
    NavigationStack {
        PublicSellerProfileView(
            seller: .sample,
            products: MockData.products
        )
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
        .environmentObject(BuyerEngagementStore(eventStore: events))
        .environmentObject(BuyerSellerThreadStore())
        .environmentObject(LocalProductStore(eventStore: events))
    }
}

#Preview("Empty Seller") {
    let events = CommerceEventStore()
    NavigationStack {
        PublicSellerProfileView(
            seller: .sampleSecond,
            products: []
        )
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
        .environmentObject(BuyerEngagementStore(eventStore: events))
        .environmentObject(BuyerSellerThreadStore())
        .environmentObject(LocalProductStore(eventStore: events))
    }
}
