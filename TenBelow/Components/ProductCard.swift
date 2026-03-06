//
//  ProductCard.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI

struct ProductCard: View {
    let product: Product
    var seller: SellerProfile? = nil
    var allProducts: [Product] = []

    var body: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
            NavigationLink {
                ProductDetailView(product: product)
            } label: {
                VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                    Image(product.imageNames.first ?? "")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 130)
                        .clipped()
                        .cornerRadius(TBTheme.radiusMD)
                        .shadow(color: TBTheme.deepSky.opacity(0.10), radius: 4, y: 2)

                    Text(product.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                        .shadow(color: TBTheme.skyBlue.opacity(0.18), radius: 2, y: 1)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let seller {
                NavigationLink {
                    PublicSellerProfileView(
                        seller: seller,
                        products: allProducts.isEmpty ? [product] : allProducts
                    )
                } label: {
                    HStack(spacing: 4) {
                        Text(seller.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(TBTheme.icyBlue)
                        if seller.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(TBTheme.accent)
                        }
                    }
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(TBTheme.spacingMD)
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
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.9),
                            TBTheme.skyBlue.opacity(0.25),
                            TBTheme.deepSky.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: TBTheme.deepSky.opacity(0.1), radius: 2, x: 0, y: 1)
        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
        .shadow(color: TBTheme.skyBlue.opacity(0.06), radius: 16, y: 8)
    }
}

#Preview {
    NavigationStack {
        ProductCard(
            product: MockData.products[0],
            seller: .mockLookup(id: MockData.products[0].sellerId),
            allProducts: MockData.products
        )
        .frame(width: 180)
        .padding()
    }
}
