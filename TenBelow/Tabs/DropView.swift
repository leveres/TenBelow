//
//  DropView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import Combine

struct DropView: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalog: CatalogStore
    @State private var showCart = false
    @State private var dropResponse: CurrentDropResponse?
    @State private var isLoading = true

    private var isActive: Bool { dropResponse?.active == true }
    private var dropProducts: [DropProduct] { dropResponse?.products ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isActive && !dropProducts.isEmpty {
                    activeDropContent
                } else {
                    inactiveDropContent
                }
            }
            .background(TBTheme.cloudWhite)
            .navigationTitle("")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CartButton(itemCount: cart.items.reduce(0) { $0 + $1.quantity }) {
                        showCart = true
                    }
                }
            }
            #else
            .toolbar {
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
            .task { await loadDrop() }
            .refreshable { await loadDrop() }
        }
    }

    // MARK: - Active drop

    @ViewBuilder
    private var activeDropContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TBTheme.spacingMD) {

                Image("WeeklyDropTitle")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 38)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Hero banner
                VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                            .fill(TBTheme.dropBannerGradient)
                            .frame(height: 180)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("This Week's Drop")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                            Text("Premium products • Over $10 • Limited")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(TBTheme.spacingLG)
                    }

                    if let resp = dropResponse {
                        HStack {
                            Text(DropCountdown.timeLeft(until: resp.endsAt))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(TBTheme.accent)
                                .clipShape(Capsule())

                            Spacer()

                            Text("\(dropProducts.count) product\(dropProducts.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text("Premium 3D-printed products from sellers across the platform. These items go over the usual $10 limit — available this weekend only.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                // Drop products
                VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                    Text("This Week's Items")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.frostTitleGradient)

                    ForEach(dropProducts) { product in
                        DropProductRow(product: product)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom)
        }
    }

    // MARK: - Inactive / empty drop

    @ViewBuilder
    private var inactiveDropContent: some View {
        VStack(spacing: TBTheme.spacingMD) {
            Image("WeeklyDropTitle")
                .resizable()
                .scaledToFit()
                .frame(height: 38)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)

            Spacer()

            Image(systemName: "flame")
                .font(.system(size: 56))
                .foregroundStyle(TBTheme.skyBlue.opacity(0.4))

            Text("No Drop This Weekend")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.frostTitleGradient)

            if let next = dropResponse?.nextDropAt {
                Text("Next drop opens \(DropCountdown.timeLeft(until: next))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Sellers can submit premium products every Friday through Sunday")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom)
    }

    // MARK: - Load

    private func loadDrop() async {
        do {
            dropResponse = try await DropAPI.currentDrop()
        } catch {
            print("Failed to load drop: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Drop Product Row (uses DropProduct instead of Product)

private struct DropProductRow: View {
    let product: DropProduct

    var body: some View {
        HStack(spacing: TBTheme.spacingMD) {
            RoundedRectangle(cornerRadius: TBTheme.radiusMD)
                .fill(TBTheme.heroGradient)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "cube.fill")
                        .font(.title2)
                        .foregroundStyle(TBTheme.skyBlue)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                Text(Money.format(cents: product.priceCents))
                    .font(.tbPriceSmall)
                    .foregroundStyle(TBTheme.icyBlue)

                Text(product.material)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Seller")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(product.sellerId.replacingOccurrences(of: "seller_", with: "#"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TBTheme.skyBlue)
            }
        }
        .padding(TBTheme.spacingMD)
        .background(TBTheme.cardGradient)
        .cornerRadius(TBTheme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .strokeBorder(TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
        )
    }
}

#Preview {
    DropView()
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
}
