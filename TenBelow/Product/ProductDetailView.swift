//
//  ProductDetailView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import AVKit
import Combine

struct ProductDetailView: View {
    @EnvironmentObject private var cart: CartStore
    @Environment(\.openURL) private var openURL
    let product: Product

    @State private var addedToCart = false
    @State private var buttonScale: CGFloat = 1.0

    private func reportListing(product: Product) {
        let subject = "Report Listing: \(product.name) (\(product.id))"
        let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(AppConstants.reportListingEmail)?subject=\(encoded)") {
            openURL(url)
        }
    }

    private func handleAddToCart() {
        cart.add(product)

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            buttonScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                buttonScale = 1.0
            }
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            addedToCart = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.3)) {
                addedToCart = false
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: TBTheme.spacingLG) {

                    // Media
                    TabView {
                        ForEach(product.imageNames, id: \.self) { name in
                            Image(name)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 320)
                                .clipped()
                        }

                        if let url = product.demoVideoURL {
                            VideoPlayer(player: AVPlayer(url: url))
                                .frame(height: 320)
                                .cornerRadius(0)
                        }
                    }
                    .frame(height: 320)
                    #if os(iOS) || os(visionOS)
                    .tabViewStyle(.page)
                    #endif

                    // Title + Price
                    VStack(alignment: .leading, spacing: 6) {
                        Text(product.name)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(TBTheme.frostTitleGradient)

                        Text(Money.format(cents: product.priceCents))
                            .font(.tbPrice)
                            .foregroundStyle(TBTheme.icyBlue)

                        Text("Printed fresh when you order")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Ships from seller")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Quick facts
                    VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                        Text("Quick facts")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(TBTheme.icyBlue)

                        LabeledContent("Material", value: product.material)
                        LabeledContent("Ships", value: "\(product.shipsInDays.lowerBound)–\(product.shipsInDays.upperBound) business days")
                        LabeledContent("Category", value: product.category.rawValue)
                    }
                    .padding(TBTheme.spacingMD)
                    .background(TBTheme.cardGradient)
                    .cornerRadius(TBTheme.radiusLG)

                    // Durability note
                    VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                        Text("Durability")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(TBTheme.icyBlue)
                        Text(product.durabilityNote)
                            .foregroundStyle(.secondary)
                    }

                    // Care + warnings
                    VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                        Text("Care & Warnings")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(TBTheme.icyBlue)

                        ForEach(product.careWarnings, id: \.self) { w in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                Text(w)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        handleAddToCart()
                    } label: {
                        HStack(spacing: 8) {
                            if addedToCart {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .transition(.scale.combined(with: .opacity))
                                Text("Added!")
                                    .font(.headline)
                            } else {
                                Text("Add to Cart")
                                    .font(.headline)
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .scaleEffect(buttonScale)
                    .padding(.top, 6)

                    Button {
                        reportListing(product: product)
                    } label: {
                        Label("Report Listing", systemImage: "flag")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }

            // Toast banner
            if addedToCart {
                AddedToCartToast(productName: product.name)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .navigationTitle("")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct AddedToCartToast: View {
    let productName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cart.badge.plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)

            Text("\(productName) added to cart")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [TBTheme.accent, TBTheme.skyBlue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: TBTheme.accent.opacity(0.35), radius: 12, y: 6)
        )
        .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        ProductDetailView(product: MockData.products[0])
    }
    .environmentObject(CartStore())
}
