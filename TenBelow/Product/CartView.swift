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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var phase: CheckoutPhase = .cart
    @State private var receiptItems: [CartItem] = []

    private var minimumOrderCents: Int {
        catalog.config.minimumOrderCents
    }

    private var phaseTitle: String {
        switch phase {
        case .cart: return "Cart"
        case .checkout: return "Checkout"
        case .receipt: return "Order Confirmed"
        }
    }

    private var itemsBySeller: [(sellerId: String, items: [CartItem])] {
        Dictionary(grouping: cart.items, by: { $0.product.sellerId })
            .sorted { $0.key < $1.key }
            .map { (sellerId: $0.key, items: $0.value) }
    }

    var body: some View {
        NavigationStack {
            Group {
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
            .navigationTitle(phaseTitle)
            .navigationBarTitleDisplayMode(.inline)
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
                        Button("Clear") {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            cart.clear()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .background(TBTheme.cloudWhite.ignoresSafeArea())
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
        VStack(spacing: TBTheme.spacingXL) {
            Spacer()

            ZStack {
                Circle()
                    .fill(TBTheme.skyLight.opacity(0.6))
                    .frame(width: 120, height: 120)

                Image(systemName: "bag")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(TBTheme.icyBlue)
            }

            VStack(spacing: TBTheme.spacingSM) {
                Text("Your cart is empty")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                Text("Add 3D-printed finds $10 and under.\nWe'll print them fresh when you order.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 32)

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                dismiss()
            } label: {
                Text("Continue Shopping")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .buttonStyle(PrimaryCTAButtonStyle())
            .frame(width: 220)
            .padding(.top, 8)

            Spacer()
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
                    GlassCard(cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                            HStack(spacing: 6) {
                                Image(systemName: "storefront")
                                    .font(.caption)
                                Text("Ships from \(group.sellerId.replacingOccurrences(of: "seller_", with: "Seller #"))")
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

                GlassCard(cornerRadius: 22) {
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
                        Text("Minimum order \(Money.format(cents: minimumOrderCents)) for free shipping.")
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
                if let name = item.product.imageNames.first {
                    Image(name)
                        .resizable()
                        .scaledToFill()
                } else {
                    TBTheme.skyLight.opacity(0.5)
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
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
}
