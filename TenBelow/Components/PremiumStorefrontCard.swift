import SwiftUI

struct PremiumStorefrontCardContent: Equatable {
    let seller: SellerProfile
    let products: [Product]
    let isCurrentSeller: Bool

    // Derived once at init: the card body reads these repeatedly, and recomputing
    // filter/sort passes per property access was measurable in directory scrolling.
    let displayedProducts: [Product]
    let thumbnailReferences: [String]
    let categories: [Category]
    let creatorClipURL: URL?
    let effectiveRating: Double
    let effectiveReviewCount: Int
    let productCount: Int
    let isFastShipping: Bool
    let isTopRated: Bool

    init(seller: SellerProfile, products: [Product], isCurrentSeller: Bool) {
        self.seller = seller
        self.products = products
        self.isCurrentSeller = isCurrentSeller

        let displayed = products
            .filter { CatalogSeedPolicy.hasUploadedMedia(in: $0.imageNames) }
            .sorted { $0.createdAt > $1.createdAt }
        displayedProducts = displayed

        thumbnailReferences = displayed
            .compactMap(\.primaryImageReference)
            .prefix(3)
            .map { $0 }

        var seen = Set<Category>()
        categories = products.compactMap { product in
            guard seen.insert(product.category).inserted else { return nil }
            return product.category
        }
        .prefix(3)
        .map { $0 }

        creatorClipURL = displayed.compactMap(\.demoVideoURL).first

        let rating: Double
        if seller.rating > 0 {
            rating = seller.rating
        } else {
            let reviewedProducts = products.filter { $0.averageRating > 0 && $0.reviewCount > 0 }
            let reviewCount = reviewedProducts.reduce(0) { $0 + $1.reviewCount }
            if reviewCount > 0 {
                let weightedTotal = reviewedProducts.reduce(0.0) {
                    $0 + ($1.averageRating * Double($1.reviewCount))
                }
                rating = weightedTotal / Double(reviewCount)
            } else {
                rating = 0
            }
        }
        effectiveRating = rating

        let reviewCount = max(seller.totalReviewCount, products.reduce(0) { $0 + $1.reviewCount })
        effectiveReviewCount = reviewCount
        productCount = max(seller.productCount, products.count)
        isFastShipping = seller.shipsInDays.lowerBound > 0 && seller.shipsInDays.upperBound <= 2
        isTopRated = rating >= 4.7 && reviewCount >= 10
    }

    static func == (lhs: PremiumStorefrontCardContent, rhs: PremiumStorefrontCardContent) -> Bool {
        lhs.seller == rhs.seller
            && lhs.products == rhs.products
            && lhs.isCurrentSeller == rhs.isCurrentSeller
    }
}

struct PremiumStorefrontCard: View {
    let content: PremiumStorefrontCardContent

    private var seller: SellerProfile { content.seller }

    var body: some View {
        VStack(spacing: 0) {
            banner
            storefrontDetails
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    content.isCurrentSeller ? TBTheme.frostEdgeOnDark : TBTheme.frostEdge,
                    lineWidth: content.isCurrentSeller ? 1.4 : 1
                )
        }
        .shadow(
            color: content.isCurrentSeller
                ? TBTheme.accent.opacity(0.20)
                : TBTheme.deepSky.opacity(0.10),
            radius: content.isCurrentSeller ? 18 : 12,
            y: 7
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(content.isCurrentSeller ? "Returns to your seller dashboard" : "Opens this seller's store")
    }

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            StorefrontImageView(reference: seller.bannerMediaReference, contentMode: .fill) {
                LinearGradient(
                    colors: content.isCurrentSeller
                        ? [TBTheme.deepSky, TBTheme.accent, TBTheme.skyBlue]
                        : [TBTheme.skyBlue, TBTheme.deepSky.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.58)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 8) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(content.isCurrentSeller ? "My Store" : seller.displayName)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        if seller.showsVerifiedBadge {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .accessibilityLabel("Verified seller")
                        }
                    }

                    Text(content.isCurrentSeller ? seller.displayName : seller.handle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if content.creatorClipURL != nil {
                    Label("Creator Clip", systemImage: "play.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.28), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(.white.opacity(0.38), lineWidth: 0.8)
                        }
                        .accessibilityLabel("Creator clip available")
                }
            }
            .padding(8)
        }
        .frame(height: 82)
    }

    private var avatar: some View {
        StorefrontImageView(reference: seller.avatarMediaReference, contentMode: .fill) {
            Circle()
                .fill(.white.opacity(0.96))
                .overlay {
                    Text(avatarInitials)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.20), radius: 7, y: 3)
    }

    private var storefrontDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !content.isCurrentSeller {
                badges
            }
            metrics

            if !content.categories.isEmpty {
                categoryChips
            }

            if !content.thumbnailReferences.isEmpty {
                productPreviews
            }

            actionRow
        }
        .padding(8)
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 6) {
            if seller.showsVerifiedBadge {
                Label("Verified", systemImage: "checkmark.seal.fill")
                    .storefrontBadge(foreground: TBTheme.deepSky)
            }
            if content.isTopRated {
                Label("Top Rated", systemImage: "star.fill")
                    .storefrontBadge(foreground: .orange)
            }
            if content.isFastShipping {
                Label("Fast Shipping", systemImage: "bolt.fill")
                    .storefrontBadge(foreground: TBTheme.deepSky)
            }
        }
    }

    private var metrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                metric(icon: "cube.box.fill", value: "\(content.productCount)", label: "Products")
                metric(icon: "cart.fill", value: "\(seller.orderCount)", label: "Sales")
                if content.effectiveRating > 0 {
                    metric(
                        icon: "star.fill",
                        value: String(format: "%.1f", content.effectiveRating),
                        label: "\(content.effectiveReviewCount) reviews"
                    )
                }
                shippingMetric
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    metric(icon: "cube.box.fill", value: "\(content.productCount)", label: "Products")
                    metric(icon: "cart.fill", value: "\(seller.orderCount)", label: "Sales")
                }
                HStack(spacing: 10) {
                    if content.effectiveRating > 0 {
                        metric(
                            icon: "star.fill",
                            value: String(format: "%.1f", content.effectiveRating),
                            label: "\(content.effectiveReviewCount) reviews"
                        )
                    }
                    shippingMetric
                }
            }
        }
    }

    private var shippingMetric: some View {
        metric(
            icon: "shippingbox.fill",
            value: shippingValue,
            label: "Shipping"
        )
    }

    private func metric(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TBTheme.icyBlue)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TBTheme.deepSky)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var categoryChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(content.categories) { category in
                    categoryChip(category)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(content.categories) { category in
                    categoryChip(category)
                }
            }
        }
    }

    private func categoryChip(_ category: Category) -> some View {
        Label(category.rawValue, systemImage: category.icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(TBTheme.deepSky)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TBTheme.skyLight.opacity(0.32), in: Capsule())
    }

    private var productPreviews: some View {
        HStack(spacing: 6) {
            ForEach(Array(content.thumbnailReferences.enumerated()), id: \.offset) { _, reference in
                StorefrontImageView(reference: reference, contentMode: .fill) {
                    productPlaceholder
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            ForEach(content.thumbnailReferences.count..<3, id: \.self) { _ in
                productPlaceholder
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
        }
    }

    private var productPlaceholder: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(TBTheme.skyLight.opacity(0.25))
            .overlay {
                Image(systemName: "cube.transparent")
                    .foregroundStyle(TBTheme.icyBlue.opacity(0.55))
            }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Text(actionContextText)
                .font(.caption2.weight(content.thumbnailReferences.isEmpty ? .semibold : .medium))
                .foregroundStyle(content.thumbnailReferences.isEmpty ? TBTheme.deepSky : .secondary)
                .lineLimit(2)

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                Text(content.isCurrentSeller ? "View Dashboard" : "Explore Store")
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                LinearGradient(
                    colors: [TBTheme.accent, TBTheme.deepSky],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .shadow(color: TBTheme.accent.opacity(0.22), radius: 7, y: 3)
        }
    }

    private var avatarInitials: String {
        let initials = seller.displayName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
        return initials.isEmpty ? "TB" : initials
    }

    private var shippingValue: String {
        let range = seller.shipsInDays
        guard range.lowerBound > 0 else { return "Ask seller" }
        if range.lowerBound == range.upperBound {
            return "\(range.lowerBound) day\(range.lowerBound == 1 ? "" : "s")"
        }
        return "\(range.lowerBound)–\(range.upperBound) days"
    }

    private var joinedText: String {
        "Joined \(seller.joinedAt.formatted(.dateTime.month(.abbreviated).year()))"
    }

    private var actionContextText: String {
        guard content.thumbnailReferences.isEmpty else { return joinedText }
        return content.isCurrentSeller ? "Add your first product" : "Products coming soon"
    }

    private var accessibilityDescription: String {
        var details = [
            content.isCurrentSeller ? "My Store, \(seller.displayName)" : seller.displayName,
            "\(content.productCount) products",
            "\(seller.orderCount) sales",
            "ships in \(shippingValue)",
        ]
        if content.effectiveRating > 0 {
            details.append("\(String(format: "%.1f", content.effectiveRating)) stars")
        }
        return details.joined(separator: ", ")
    }
}

struct PremiumStorefrontCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 1.012 : 1)
            .brightness(configuration.isPressed ? 0.025 : 0)
            .shadow(
                color: configuration.isPressed ? TBTheme.accent.opacity(0.18) : .clear,
                radius: 14,
                y: 6
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.78),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, isPressed in
                #if os(iOS)
                if isPressed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                #endif
            }
    }
}

private extension View {
    func storefrontBadge(foreground: Color) -> some View {
        self
            .font(.caption2.weight(.bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.white.opacity(0.72), in: Capsule())
            .overlay {
                Capsule().strokeBorder(TBTheme.skyBlue.opacity(0.20), lineWidth: 0.8)
            }
    }
}
