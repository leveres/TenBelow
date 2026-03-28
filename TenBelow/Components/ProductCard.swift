//
//  ProductCard.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI

struct ProductCard: View {
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let product: Product
    var seller: SellerProfile? = nil
    var allProducts: [Product] = []

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
            .frame(maxWidth: .infinity, minHeight: 182, alignment: .topLeading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                        .fill(TBTheme.cardGradient)

                    RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.5), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .cornerRadius(TBTheme.radiusLG)
            .shadow(color: TBTheme.deepSky.opacity(0.1), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
            .shadow(color: TBTheme.skyBlue.opacity(0.06), radius: 16, y: 8)

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
