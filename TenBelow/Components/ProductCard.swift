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
}

struct ProductCard: View {
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let product: Product
    var seller: SellerProfile? = nil
    var allProducts: [Product] = []
    var style: ProductCardStyle = .standard

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 7) {
                NavigationLink {
                    ProductDetailView(product: product)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        StorefrontImageView(reference: product.primaryImageReference) {
                            RoundedRectangle(cornerRadius: TBTheme.radiusMD)
                                .fill(TBTheme.skyLight.opacity(0.32))
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                        }
                            .frame(height: 112)
                            .clipped()
                            .cornerRadius(TBTheme.radiusMD)
                            .shadow(color: TBTheme.deepSky.opacity(0.10), radius: 4, y: 2)

                        Text(product.name)
                            .font(.tbProductTitleSM)
                            .tracking(-0.2)
                            .tbProductNameTitleStyle()
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(productAccessibilityLabel)
                .accessibilityHint("Opens product details.")

                if let seller {
                    NavigationLink {
                        PublicSellerProfileView(
                            seller: seller,
                            products: allProducts.isEmpty ? [product] : allProducts
                        )
                    } label: {
                        HStack(spacing: 4) {
                            Text(seller.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(TBTheme.icyBlue)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                                .multilineTextAlignment(.leading)
                            if seller.showsVerifiedBadge {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption2)
                                    .foregroundStyle(TBTheme.accent)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View seller \(seller.displayName)")
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .topLeading)
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
                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .strokeBorder(cardBorderColor, lineWidth: style == .blended ? 0.8 : 0)
            )
            .cornerRadius(TBTheme.radiusLG)
            .shadow(color: primaryShadowColor, radius: primaryShadowRadius, x: 0, y: primaryShadowYOffset)
            .shadow(color: secondaryShadowColor, radius: secondaryShadowRadius, y: secondaryShadowYOffset)

            if buyerEngagement.showsFavoriteButton(for: product) {
                Button {
                    let isNowFavorited = buyerEngagement.toggleFavorite(for: product)
                    localProducts.setFavoriteState(for: product.id, isFavorited: isNowFavorited)
                } label: {
                    Image(systemName: buyerEngagement.isProductFavorited(product.id) ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(buyerEngagement.isProductFavorited(product.id) ? .white : TBTheme.bannerCTAForeground)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(buyerEngagement.isProductFavorited(product.id) ? TBTheme.accent : Color.white.opacity(0.92))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.88), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(14)
                .accessibilityLabel(buyerEngagement.isProductFavorited(product.id) ? "Remove from favorites" : "Add to favorites")
                .accessibilityHint(product.name)
                .zIndex(1)
            }
        }
    }

    private var productAccessibilityLabel: String {
        var parts = [product.name, Money.format(cents: product.priceCents), product.category.rawValue]
        if let seller {
            parts.append("by \(seller.displayName)")
        }
        return parts.joined(separator: ", ")
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
        }
    }

    private var cardMinHeight: CGFloat {
        switch style {
        case .standard:
            return 182
        case .blended:
            return 170
        }
    }

    private var cardBorderColor: Color {
        style == .blended ? .white.opacity(0.55) : .clear
    }

    private var primaryShadowColor: Color {
        style == .blended ? TBTheme.deepSky.opacity(0.03) : TBTheme.deepSky.opacity(0.1)
    }

    private var primaryShadowRadius: CGFloat {
        style == .blended ? 4 : 2
    }

    private var primaryShadowYOffset: CGFloat {
        style == .blended ? 1 : 1
    }

    private var secondaryShadowColor: Color {
        style == .blended ? TBTheme.skyBlue.opacity(0.025) : .black.opacity(0.1)
    }

    private var secondaryShadowRadius: CGFloat {
        style == .blended ? 8 : 12
    }

    private var secondaryShadowYOffset: CGFloat {
        style == .blended ? 3 : 6
    }
}

#Preview {
    let events = CommerceEventStore()
    return NavigationStack {
        ProductCard(
            product: MockData.products[0],
            seller: .mockLookup(id: MockData.products[0].sellerId),
            allProducts: MockData.products
        )
        .frame(width: 180)
        .padding()
        .environmentObject(BuyerEngagementStore(eventStore: events))
        .environmentObject(LocalProductStore(eventStore: events))
    }
}
