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
    @AppStorage("userRole") private var userRole = ""
    @State private var showCart = false
    @State private var liveDrop: CurrentDropResponse?
    private let products = MockData.products
    private let drop = MockData.currentDrop

    @ViewBuilder
    private var profileDestination: some View {
        if userRole == "seller" {
            SellerProfileView()
        } else {
            BuyerProfileView()
        }
    }

    private var hasLiveDrop: Bool {
        if let d = liveDrop, d.active, !d.products.isEmpty { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Brand logo
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, TBTheme.spacingSM)

                // Weekly Drop hero
                if hasLiveDrop, let ld = liveDrop {
                    // Live drop with real seller products
                    VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                        Text("Weekly Drop")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(TBTheme.frostTitleGradient)

                        NavigationLink {
                            DropView()
                                .environmentObject(cart)
                                .environmentObject(catalog)
                        } label: {
                            LiveDropBanner(endsAt: ld.endsAt, productCount: ld.products.count)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, TBTheme.spacingSM)
                } else if catalog.config.dropEnabled {
                    // Fallback: config-driven drop banner (always shows when enabled)
                    VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                        Text(catalog.config.dropTitle)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(TBTheme.frostTitleGradient)

                        NavigationLink {
                            DropView()
                        } label: {
                            DropHeroBanner(drop: drop, dropEndsAt: catalog.config.dropEndsAt, cta: catalog.config.dropCta)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, TBTheme.spacingSM)
                }

                // Trending products
                VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                    Text("Trending Under $10")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.frostTitleGradient)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TBTheme.spacingMD) {
                            ForEach(products.prefix(6)) { product in
                                ProductCard(
                                    product: product,
                                    seller: .mockLookup(id: product.sellerId),
                                    allProducts: products
                                )
                                .frame(width: 160)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.bottom, 88)
            .task {
                do { liveDrop = try await DropAPI.currentDrop() } catch { }
            }
            .background(TBTheme.cloudWhite)
            .navigationTitle("")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        profileDestination
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .foregroundStyle(TBTheme.icyBlue)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    CartButton(itemCount: cart.items.reduce(0) { $0 + $1.quantity }) {
                        showCart = true
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    NavigationLink {
                        profileDestination
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .foregroundStyle(TBTheme.icyBlue)
                    }
                }
                ToolbarItem(placement: .automatic) {
                    CartButton(itemCount: cart.items.reduce(0) { $0 + $1.quantity }) {
                        showCart = true
                    }
                }
            }
            #endif
            .sheet(isPresented: $showCart) {
                CartView()
                    .environmentObject(cart)
                    .environmentObject(catalog)
            }
        }
    }
}

// MARK: - Live Drop Banner (replaces old DropHeroBanner on Home)

private struct LiveDropBanner: View {
    let endsAt: String
    let productCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("Premium Products This Weekend")
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

                Text("\(productCount) item\(productCount == 1 ? "" : "s") • View Drop →")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(TBTheme.spacingLG)
        .frame(height: 120)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TBTheme.dropBannerGradient)
        .cornerRadius(TBTheme.radiusLG)
        .shadow(color: TBTheme.skyBlue.opacity(0.25), radius: 10, y: 4)
    }
}

#Preview {
    HomeView()
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
}
