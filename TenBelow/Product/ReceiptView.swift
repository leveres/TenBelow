//
//  ReceiptView.swift
//  TenBelow
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

struct ReceiptView: View {
    let orderId: String
    var items: [CartItem] = []
    var onDismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showExchangePolicyBrowser = false
    @State private var revealStep = 0

    private var itemsBySeller: [(sellerId: String, items: [CartItem])] {
        Dictionary(grouping: items, by: { $0.product.sellerId })
            .sorted { $0.key < $1.key }
            .map { (sellerId: $0.key, items: $0.value) }
    }

    private var totalCents: Int {
        let subtotal = items.reduce(0) { $0 + ($1.product.priceCents * $1.quantity) }
        return subtotal + MarketplaceShippingCalculator.totalShippingCents(for: items)
    }

    private var shippingCents: Int {
        MarketplaceShippingCalculator.totalShippingCents(for: items)
    }

    private var subtotalCents: Int {
        items.reduce(0) { $0 + ($1.product.priceCents * $1.quantity) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TBTheme.spacingXL) {

                confirmationHeader
                    .opacity(revealStep >= 1 ? 1 : 0)
                    .offset(y: revealStep >= 1 || reduceMotion ? 0 : 8)

                if !items.isEmpty {
                    GlassCard(cornerRadius: 22) {
                        VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                            ForEach(itemsBySeller, id: \.sellerId) { group in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("From \(group.sellerId.replacingOccurrences(of: "seller_", with: "Seller #"))")
                                        .font(.caption.weight(.semibold))
                                        .fontDesign(.rounded)
                                        .foregroundStyle(TBTheme.skyBlue)

                                    ForEach(group.items) { item in
                                        HStack(alignment: .top) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(item.product.name)
                                                    .font(.body.weight(.medium))
                                                    .fontDesign(.rounded)
                                                    .foregroundStyle(TBTheme.deepSky)
                                                    .lineLimit(2)
                                                if let color = item.selectedColor {
                                                    HStack(spacing: 5) {
                                                        ProductColorSwatch(hex: color.hex, size: 12)
                                                        Text("Color: \(color.name)")
                                                    }
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                            Text("\(item.quantity) × \(Money.format(cents: item.product.priceCents))")
                                                .font(.subheadline.weight(.medium))
                                                .fontDesign(.rounded)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                if group.sellerId != itemsBySeller.last?.sellerId {
                                    Divider().background(Color.secondary.opacity(0.2))
                                }
                            }

                            Divider().background(Color.secondary.opacity(0.2))

                            HStack {
                                Text("Subtotal")
                                    .font(.subheadline.weight(.medium))
                                    .fontDesign(.rounded)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Money.format(cents: subtotalCents))
                                    .font(.subheadline.weight(.semibold))
                                    .fontDesign(.rounded)
                            }

                            HStack {
                                Text("Shipping")
                                    .font(.subheadline.weight(.medium))
                                    .fontDesign(.rounded)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(shippingCents == 0 ? "Free" : Money.format(cents: shippingCents))
                                    .font(.subheadline.weight(.semibold))
                                    .fontDesign(.rounded)
                                    .foregroundStyle(shippingCents == 0 ? .green : TBTheme.deepSky)
                            }

                            Divider().background(Color.secondary.opacity(0.2))

                            HStack {
                                Text("Total")
                                    .font(.headline)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(TBTheme.deepSky)
                                Spacer()
                                Text(Money.format(cents: totalCents))
                                    .font(.title3.bold())
                                    .fontDesign(.rounded)
                                    .foregroundStyle(TBTheme.icyBlue)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .opacity(revealStep >= 2 ? 1 : 0)
                    .offset(y: revealStep >= 2 || reduceMotion ? 0 : 8)
                }

                receiptDetails
                    .opacity(revealStep >= 2 ? 1 : 0)

                exchangeActions
                    .opacity(revealStep >= 3 ? 1 : 0)

                policyLinks
                    .opacity(revealStep >= 3 ? 1 : 0)

                Button {
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .fontDesign(.rounded)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(PrimaryCTAButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 40)
                .opacity(revealStep >= 3 ? 1 : 0)
            }
            .padding(.top, TBTheme.spacingLG)
        }
        .background(TBFrostBackground())
        .onAppear {
            if reduceMotion {
                revealStep = 3
                return
            }
            withAnimation(TBMotion.stateChange) { revealStep = 1 }
            withAnimation(TBMotion.stateChange.delay(0.08)) { revealStep = 2 }
            withAnimation(TBMotion.stateChange.delay(0.16)) { revealStep = 3 }
        }
        .sensoryFeedback(.success, trigger: revealStep) { _, newValue in
            newValue == 3
        }
        .sheet(isPresented: $showExchangePolicyBrowser) {
            LegalDocumentSheet(document: .exchangePolicy)
        }
    }

    private var confirmationHeader: some View {
        VStack(spacing: TBTheme.spacingMD) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 88, height: 88)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .symbolEffect(.pulse.byLayer, options: .nonRepeating, value: revealStep >= 1)
            }
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Order confirmed!")
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(TBTheme.deepSky)

                Text("Order #\(orderId)")
                    .font(.subheadline.weight(.medium))
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var receiptDetails: some View {
        VStack(spacing: 6) {
            Text("A receipt has been emailed to you.")
                .font(.subheadline.weight(.medium))
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)

            if itemsBySeller.count > 1 {
                Text("Items may ship separately from different sellers.")
                    .font(.caption.weight(.medium))
                    .fontDesign(.rounded)
                    .foregroundStyle(.tertiary)
            }

            Text("View order status in the Orders tab.")
                .font(.caption.weight(.medium))
                .fontDesign(.rounded)
                .foregroundStyle(TBTheme.icyBlue)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }

    private var exchangeActions: some View {
        VStack(spacing: 10) {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showExchangePolicyBrowser = true
            } label: {
                Label("How exchanges work", systemImage: "arrow.triangle.2.circlepath")
                    .font(.body.weight(.semibold))
                    .fontDesign(.rounded)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(TBTheme.icyBlue)

            Text("After delivery, request an eligible exchange from the order details screen in Orders.")
                .font(.caption.weight(.medium))
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private var policyLinks: some View {
        HStack(spacing: 16) {
            Button("Exchange policy") { showExchangePolicyBrowser = true }
                .frame(minHeight: 44)
            Text("·")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Button("Contact support") {
                if let url = AppConstants.supportMailtoURL {
                    openURL(url)
                }
            }
            .frame(minHeight: 44)
        }
        .font(.caption.weight(.medium))
        .fontDesign(.rounded)
        .foregroundStyle(TBTheme.icyBlue)
    }
}

