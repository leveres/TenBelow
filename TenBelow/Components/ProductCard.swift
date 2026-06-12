//
//  ProductCard.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI

enum ProductCardStyle {
    case standard
    case blended
    case compact
}

struct ProductCard: View {
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let product: Product
    var seller: SellerProfile? = nil
    var allProducts: [Product] = []
    var style: ProductCardStyle = .standard
    /// Blue theme trim + soft glow, matching the Orders cards. Opt-in per grid.
    var showsAccentBorder: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                ProductDetailView(product: product)
            } label: {
                VStack(alignment: .leading, spacing: style == .blended ? 4 : 7) {
                    StorefrontImageView(reference: product.primaryImageReference) {
                        RoundedRectangle(cornerRadius: TBTheme.radiusMD)
                            .fill(TBTheme.skyLight.opacity(0.32))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                    }
                    .frame(height: imageHeight)
                    .clipped()
                    .cornerRadius(TBTheme.radiusMD)
                    .shadow(color: TBTheme.deepSky.opacity(0.10), radius: 4, y: 2)

                    titleRow

                    VStack(alignment: .leading, spacing: 5) {
                        priceRow
                        if !signalBadges.isEmpty {
                            signalBadgesRow
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(productAccessibilityLabel)
            .accessibilityHint("Opens product details.")

            if style == .blended {
                footerRow
                    .padding(.top, 2)
            } else if style == .compact {
                footerRow
                    .padding(.top, 4)
            } else {
                Spacer(minLength: 6)
                footerRow
            }
        }
        .padding(cardContentEdgeInsets)
        .frame(
            minWidth: nil,
            idealWidth: nil,
            maxWidth: .infinity,
            minHeight: cardMinHeight,
            idealHeight: nil,
            maxHeight: cardFixedHeight,
            alignment: .topLeading
        )
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .fill(cardFill)

                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .fill(
                        LinearGradient(
                            colors: style == .blended ? [.white.opacity(0.28), .clear] : [.white.opacity(0.5), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            Group {
                if showsAccentBorder {
                    RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                        .strokeBorder(accentBorderGradient, lineWidth: accentBorderLineWidth)
                } else {
                    RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                        .strokeBorder(cardBorderColor, lineWidth: style == .blended ? 0.8 : 0)
                }
            }
        )
        .cornerRadius(TBTheme.radiusLG)
        .shadow(color: primaryShadowColor, radius: primaryShadowRadius, x: 0, y: primaryShadowYOffset)
        .shadow(color: secondaryShadowColor, radius: secondaryShadowRadius, y: secondaryShadowYOffset)
    }

    private var productAccessibilityLabel: String {
        var parts = [product.name, Money.format(cents: product.priceCents), product.category.rawValue]
        if let seller {
            parts.append("by \(seller.displayName)")
        } else {
            parts.append("by \(SellerProfile.fallbackDisplayName(forSellerId: product.sellerId))")
        }
        return parts.joined(separator: ", ")
    }

    private var footerRow: some View {
        Group {
            if style == .blended {
                VStack(alignment: .leading, spacing: 4) {
                    sellerNameRow
                        .layoutPriority(1)

                    HStack(alignment: .center, spacing: 8) {
                        if product.reviewCount > 0 {
                            ratingBadge
                        }

                        Spacer(minLength: 0)

                        favoritePill
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            } else if style == .compact {
                VStack(alignment: .leading, spacing: 4) {
                    sellerNameRow
                    HStack {
                        Spacer(minLength: 0)
                        favoritePill
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 6) {
                    sellerNameRow

                    Spacer(minLength: 0)

                    ratingOnlyRow
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleRow: some View {
        Group {
            if style == .blended || style == .compact {
                Text(product.name)
                    .font(titleFont)
                    .tracking(-0.2)
                    .foregroundStyle(Color(red: 26 / 255, green: 61 / 255, blue: 107 / 255))
                    .lineLimit(titleLineLimit)
                    .minimumScaleFactor(titleMinimumScaleFactor)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Text(product.name)
                        .font(titleFont)
                        .tracking(-0.2)
                        .foregroundStyle(Color(red: 26 / 255, green: 61 / 255, blue: 107 / 255))
                        .lineLimit(titleLineLimit)
                        .minimumScaleFactor(titleMinimumScaleFactor)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    favoritePill
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private var favoritePill: some View {
        Group {
            if buyerEngagement.showsFavoriteButton(for: product) {
                Button {
                    let isNowFavorited = buyerEngagement.toggleFavorite(for: product)
                    localProducts.setFavoriteState(for: product.id, isFavorited: isNowFavorited)
                } label: {
                    favoritePillContent(isInteractive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(buyerEngagement.isProductFavorited(product.id) ? "Remove from favorites" : "Add to favorites")
                .accessibilityHint(product.name)
            } else {
                favoritePillContent(isInteractive: false)
            }
        }
    }

    private func favoritePillContent(isInteractive: Bool) -> some View {
        let m = favoritePillMetrics
        return HStack(spacing: 4) {
            Image(systemName: heartSymbolName(isInteractive: isInteractive))
                .font(.system(size: m.icon, weight: .semibold))
            Text(verbatim: "\(displayedFavoriteCount)")
                .font(.system(size: m.text, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(
            (isInteractive && buyerEngagement.isProductFavorited(product.id)) ? TBTheme.accent : TBTheme.deepSky
        )
        .padding(.horizontal, m.hPad)
        .padding(.vertical, m.vPad)
        .contentShape(Rectangle())
        .allowsHitTesting(isInteractive)
    }

    /// Home carousel cards: match shop legibility (larger hit target) without extra dead space below.
    private var favoritePillMetrics: (icon: CGFloat, text: CGFloat, hPad: CGFloat, vPad: CGFloat) {
        switch style {
        case .blended:
            return (13, 13, 8, 5)
        case .compact, .standard:
            return (11, 11, 6, 4)
        }
    }

    private func heartSymbolName(isInteractive: Bool) -> String {
        if !isInteractive { return "heart.fill" }
        return buyerEngagement.isProductFavorited(product.id) ? "heart.fill" : "heart"
    }

    private var ratingOnlyRow: some View {
        HStack(spacing: 10) {
            if product.reviewCount > 0 {
                ratingBadge
            }

            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: false)
    }

    private var ratingBadge: some View {
        Label {
            Text(ratingText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TBTheme.deepSky)
        } icon: {
            Image(systemName: "star.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(TBTheme.accent)
        }
        .accessibilityLabel("\(ratingText) stars")
    }

    @ViewBuilder
    private var sellerNameRow: some View {
        if let seller {
            NavigationLink {
                PublicSellerProfileView(
                    seller: seller,
                    products: allProducts.isEmpty ? [product] : allProducts
                )
            } label: {
                HStack(spacing: 6) {
                    sellerAvatarChip(for: seller)

                    HStack(spacing: 4) {
                        Text(seller.displayName)
                            .font(sellerNameFont)
                            .foregroundStyle(TBTheme.icyBlue)
                            .lineLimit(sellerNameLineLimit)
                            .minimumScaleFactor(sellerNameMinimumScaleFactor)
                            .multilineTextAlignment(.leading)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if seller.showsVerifiedBadge {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(
                                    Color(red: 42 / 255, green: 109 / 255, blue: 181 / 255),
                                    in: Circle()
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(.white.opacity(0.92), lineWidth: 1.5)
                                )
                                .layoutPriority(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View seller \(seller.displayName)")
        } else {
            Text(SellerProfile.fallbackDisplayName(forSellerId: product.sellerId))
                .font(sellerNameFont)
                .foregroundStyle(TBTheme.icyBlue)
                .lineLimit(sellerNameLineLimit)
                .minimumScaleFactor(sellerNameMinimumScaleFactor)
                .multilineTextAlignment(.leading)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Seller \(SellerProfile.fallbackDisplayName(forSellerId: product.sellerId))")
        }
    }

    @ViewBuilder
    private func sellerAvatarChip(for seller: SellerProfile) -> some View {
        let side: CGFloat = style == .blended ? 22 : 20
        StorefrontImageView(reference: seller.avatarURL?.absoluteString, contentMode: .fill) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.96), TBTheme.skyLight.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: side * 0.45, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(TBTheme.deepSky.opacity(0.55))
                }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(TBTheme.skyBlue.opacity(0.16), lineWidth: 0.6)
        )
        .accessibilityHidden(true)
    }

    private var cardFill: LinearGradient {
        switch style {
        case .standard:
            return TBTheme.cardGradient
        case .blended:
            return LinearGradient(
                colors: [TBTheme.cloudWhite.opacity(0.86), TBTheme.skyLight.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .compact:
            return TBTheme.cardGradient
        }
    }

    private var cardMinHeight: CGFloat {
        switch style {
        case .standard:
            return 182
        case .blended:
            // Height comes from content; avoid a floor that pulls the footer away from the price.
            return 0
        case .compact:
            return 182
        }
    }

    /// Blended (home) cards size to their content so the seller row sits tight under the title/price.
    /// Compact cards in grids still use a fixed height for alignment.
    private var cardFixedHeight: CGFloat? {
        switch style {
        case .blended:
            return nil
        case .compact:
            guard !dynamicTypeSize.isAccessibilitySize else { return nil }
            return 192
        case .standard:
            return nil
        }
    }

    private var cardBorderColor: Color {
        style == .blended ? .white.opacity(0.55) : .clear
    }

    private var accentBorderLineWidth: CGFloat {
        switch style {
        case .compact: return 1.1
        case .blended: return 1.0
        case .standard: return 1.3
        }
    }

    private var accentBorderGradient: LinearGradient {
        TBTheme.frostEdge
    }

    private var primaryShadowColor: Color {
        switch style {
        case .blended:
            return TBTheme.deepSky.opacity(0.03)
        case .standard, .compact:
            return TBTheme.deepSky.opacity(showsAccentBorder ? 0.13 : 0.1)
        }
    }

    private var primaryShadowRadius: CGFloat {
        switch style {
        case .blended:
            return 4
        case .standard, .compact:
            return 2
        }
    }

    private var primaryShadowYOffset: CGFloat {
        style == .blended ? 1 : 1
    }

    private var secondaryShadowColor: Color {
        switch style {
        case .blended:
            return TBTheme.skyBlue.opacity(0.025)
        case .standard, .compact:
            return .black.opacity(0.1)
        }
    }

    private var secondaryShadowRadius: CGFloat {
        switch style {
        case .blended:
            return 8
        case .standard:
            return 12
        case .compact:
            return 8
        }
    }

    private var secondaryShadowYOffset: CGFloat {
        switch style {
        case .blended:
            return 3
        case .standard:
            return 6
        case .compact:
            return 4
        }
    }

    private var imageHeight: CGFloat {
        switch style {
        case .compact:
            return 72
        case .standard:
            return 112
        case .blended:
            return 84
        }
    }

    private var cardContentEdgeInsets: EdgeInsets {
        switch style {
        case .compact:
            return EdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
        case .blended:
            // Home carousel cards need enough footer padding for seller names and favorite pills.
            return EdgeInsets(top: 7, leading: 8, bottom: 8, trailing: 8)
        case .standard:
            return EdgeInsets(top: 9, leading: 9, bottom: 9, trailing: 9)
        }
    }

    private var verifiedSealFont: Font {
        switch style {
        case .blended:
            return .system(size: 14, weight: .semibold)
        case .standard:
            return .system(size: 13, weight: .semibold)
        case .compact:
            return .caption2
        }
    }

    private var titleFont: Font {
        switch style {
        case .compact:
            return .system(size: 13, weight: .bold, design: .rounded)
        case .standard, .blended:
            return .tbProductTitleSM
        }
    }

    private var titleLineLimit: Int {
        switch style {
        case .compact:
            return dynamicTypeSize.isAccessibilitySize ? 4 : 3
        case .standard, .blended:
            return 2
        }
    }

    private var titleMinimumScaleFactor: CGFloat {
        switch style {
        case .compact:
            return 0.88
        case .standard, .blended:
            return 0.9
        }
    }

    private var sellerNameFont: Font {
        switch style {
        case .compact:
            return .system(size: 10, weight: .semibold, design: .rounded)
        case .blended:
            // Match standard / category cards — same weight as Shop grid, larger than old 12pt blended.
            return .system(size: 13, weight: .semibold, design: .rounded)
        case .standard:
            return .system(size: 13, weight: .semibold, design: .rounded)
        }
    }

    private var sellerNameLineLimit: Int {
        switch style {
        case .blended:
            return 2
        case .compact:
            return dynamicTypeSize.isAccessibilitySize ? 3 : 2
        case .standard:
            return dynamicTypeSize.isAccessibilitySize ? 2 : 1
        }
    }

    private var sellerNameMinimumScaleFactor: CGFloat {
        switch style {
        case .blended:
            return 0.8
        case .compact:
            return 0.82
        case .standard:
            return dynamicTypeSize.isAccessibilitySize ? 1.0 : 0.78
        }
    }

    private var displayedFavoriteCount: Int {
        localProducts.product(withId: product.id)?.favoriteCount ?? product.favoriteCount
    }

    private var ratingText: String {
        String(format: "%.1f", product.averageRating)
    }

    private var priceRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Money.format(cents: product.priceCents))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 74 / 255, green: 127 / 255, blue: 170 / 255))

            if let previousPriceCents = product.previousPriceCents, previousPriceCents > product.priceCents {
                Text(Money.format(cents: previousPriceCents))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .strikethrough()
            }
        }
    }

    private var signalBadges: [(String, String)] {
        var badges: [(String, String)] = []
        if product.hasPriceDrop {
            badges.append(("tag.fill", "Price drop"))
        }
        return Array(badges.prefix(style == .compact ? 2 : 3))
    }

    private var signalBadgesRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(signalBadges.enumerated()), id: \.offset) { _, badge in
                Label(badge.1, systemImage: badge.0)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(TBTheme.skyBlue.opacity(0.10), in: Capsule())
                    .foregroundStyle(TBTheme.icyBlue)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

