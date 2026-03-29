//
//  CartView.swift
//  TenBelow
//

import SwiftUI
import Combine

#if os(iOS)
import UIKit
#endif

enum CheckoutPhase {
    case cart
    case checkout
    case receipt(orderId: String)
}

struct CartView: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var phase: CheckoutPhase = .cart
    @State private var receiptItems: [CartItem] = []
    @State private var cartUpdateMessage: String?

    private var minimumOrderCents: Int {
        catalog.config.minimumOrderCents
    }

    private var phaseTitle: String {
        switch phase {
        case .cart: return "Cart"
        case .checkout: return "Checkout"
        case .receipt: return "Order confirmed"
        }
    }

    private var itemsBySeller: [(sellerId: String, items: [CartItem])] {
        Dictionary(grouping: cart.items, by: { $0.product.sellerId })
            .sorted { $0.key < $1.key }
            .map { (sellerId: $0.key, items: $0.value) }
    }

    private var availableProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var sellerProfilesByID: [String: SellerProfile] {
        resolvedSellerProfilesByID(
            storefrontProducts: availableProducts,
            remoteProfiles: catalog.sellerProfiles
        )
    }

    private var cartRefreshFingerprint: String {
        let remoteFingerprint = catalog.products
            .map { "\($0.id):\($0.priceCents):\($0.isActive):\($0.isApproved)" }
            .joined(separator: "|")
        let fallbackFingerprint = localProducts.products
            .map { "\($0.id):\($0.priceCents)" }
            .joined(separator: "|")
        return "\(remoteFingerprint)#\(fallbackFingerprint)"
    }

    private var isShowingReceipt: Bool {
        if case .receipt = phase {
            return true
        }
        return false
    }

    private func sellerDisplayName(for sellerId: String) -> String {
        sellerProfilesByID[sellerId]?.displayName ?? sellerId
    }

    var body: some View {
        NavigationStack {
            Group {
                VStack(spacing: 12) {
                    if let cartUpdateMessage, !isShowingReceipt {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(TBTheme.skyBlue)
                            Text(cartUpdateMessage)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(TBTheme.deepSky)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal)
                    }

                    switch phase {
                    case .cart:
                        cartContent
                    case .checkout:
                        CheckoutView(onSuccess: { orderId in
                            receiptItems = cart.items
                            phase = .receipt(orderId: orderId)
                        })
                    case .receipt(let orderId):
                        ReceiptView(orderId: orderId, items: receiptItems) {
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(phaseTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: cartRefreshFingerprint) {
                let removedCount = cart.syncAvailableProducts(availableProducts)
                if removedCount > 0 {
                    cartUpdateMessage = removedCount == 1
                        ? "Your cart was updated because an item is no longer available."
                        : "Your cart was updated because some items are no longer available."
                    if case .checkout = phase, cart.items.isEmpty {
                        phase = .cart
                    }
                } else if !cart.items.isEmpty {
                    cartUpdateMessage = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    switch phase {
                    case .receipt:
                        EmptyView()
                    case .checkout:
                        Button("Back") {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            phase = .cart
                        }
                        .foregroundStyle(TBTheme.icyBlue)
                    case .cart:
                        Button("Close") {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            dismiss()
                        }
                        .foregroundStyle(TBTheme.icyBlue)
                    }
                }

                if case .cart = phase, !cart.items.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear cart") {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            cart.clear()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        TBTheme.cloudWhite,
                        TBTheme.skyLight.opacity(0.2),
                        TBTheme.cloudWhite
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
        }
    }

    // MARK: - Cart Content

    @ViewBuilder
    private var cartContent: some View {
        if cart.items.isEmpty {
            emptyCartView
        } else {
            cartWithItemsView
        }
    }

    private var emptyCartView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    TBTheme.cloudWhite,
                    TBTheme.skyLight.opacity(0.2),
                    TBTheme.cloudWhite
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: TBTheme.spacingXL) {
                Spacer()

                // Icon — liquid glass orb
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 140, height: 140)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.9), TBTheme.skyBlue.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: TBTheme.deepSky.opacity(0.08), radius: 24, y: 8)
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

                    Image(systemName: "bag.fill")
                        .font(.system(size: 52, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [TBTheme.deepSky, TBTheme.skyBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                // Text — frosted glass card
                VStack(spacing: TBTheme.spacingSM) {
                    Text("Your cart is empty")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .tracking(-0.3)
                        .foregroundStyle(TBTheme.deepSky)

                    Text("Discover 3D-printed finds under $10.\nEach order is printed fresh.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.8), .white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .padding(.horizontal, 24)

                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    dismiss()
                } label: {
                    Text("Continue Shopping")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .buttonStyle(GlassPillButtonStyle(isFinal: true))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 48)
                .padding(.top, 8)

                Spacer()
            }
        }
    }

    private var cartWithItemsView: some View {
        ScrollView {
            VStack(spacing: TBTheme.spacingLG) {

                if itemsBySeller.count > 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox.fill")
                            .font(.caption)
                        Text("Items may ship separately from different sellers.")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                }

                ForEach(itemsBySeller, id: \.sellerId) { group in
                    GlassCard(cornerRadius: 20, showsBorder: false) {
                        VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                            HStack(spacing: 6) {
                                Image("Logo")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(4)
                                    .frame(width: 24, height: 24)
                                    .background(Color.white.opacity(0.92), in: Circle())
                                    .overlay(
                                        Circle()
                                            .strokeBorder(TBTheme.skyBlue.opacity(0.18), lineWidth: 1)
                                    )
                                Text("Ships from \(sellerDisplayName(for: group.sellerId))")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(TBTheme.skyBlue)
                            }

                            ForEach(group.items) { item in
                                CartRow(item: item)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                GlassCard(cornerRadius: 22, showsBorder: false) {
                    VStack(spacing: TBTheme.spacingMD) {
                        row("Subtotal", value: Money.format(cents: cart.subtotalCents))
                        row("Shipping", value: "FREE", valueColor: .green)
                        Divider().background(Color.secondary.opacity(0.2))
                        HStack {
                            Text("Total")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(TBTheme.deepSky)
                            Spacer()
                            Text(Money.format(cents: cart.subtotalCents))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(TBTheme.icyBlue)
                        }
                    }
                }
                .padding(.horizontal)

                if cart.subtotalCents < minimumOrderCents {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                        Text("Minimum order: \(Money.format(cents: minimumOrderCents)).")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                }

                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    phase = .checkout
                } label: {
                    HStack {
                        Text("Proceed to Checkout")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .buttonStyle(PrimaryCTAButtonStyle())
                .disabled(cart.subtotalCents < minimumOrderCents)
                .opacity(cart.subtotalCents >= minimumOrderCents ? 1 : 0.6)
                .padding(.horizontal)
                .padding(.top, 4)

                policyLinks
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
            .padding(.top, TBTheme.spacingMD)
        }
    }

    private func row(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor)
        }
    }

    private var policyLinks: some View {
        HStack(spacing: 16) {
            Button("Terms") { openURL(AppConstants.termsURL) }
            Text("·").foregroundStyle(.tertiary)
            Button("Privacy") { openURL(AppConstants.privacyPolicyURL) }
            Text("·").foregroundStyle(.tertiary)
            Button("Refunds") { openURL(AppConstants.refundPolicyURL) }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
    }
}

// MARK: - Cart Row

private struct CartRow: View {
    @EnvironmentObject private var cart: CartStore
    let item: CartItem

    var body: some View {
        HStack(alignment: .top, spacing: TBTheme.spacingMD) {
            ZStack {
                StorefrontImageView(reference: item.product.primaryImageReference) {
                    ZStack {
                        TBTheme.skyLight.opacity(0.5)
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: TBTheme.radiusMD))
                .overlay(
                    RoundedRectangle(cornerRadius: TBTheme.radiusMD)
                        .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.product.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
                    .lineLimit(2)

                Text(Money.format(cents: item.product.priceCents))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.icyBlue)

                HStack(spacing: 8) {
                    Stepper(value: Binding(
                        get: { item.quantity },
                        set: { newQty in
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            cart.setQuantity(item.product, qty: newQty)
                        }
                    ), in: 1...25) {
                        Text("Qty \(item.quantity)")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .labelsHidden()
                }
            }

            Spacer(minLength: 8)

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                cart.remove(item.product)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.product.name)")
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    CartView()
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
        .environmentObject(LocalProductStore(eventStore: CommerceEventStore()))
}
