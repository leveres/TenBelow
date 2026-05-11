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
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @State private var showExchangePolicyBrowser = false

    private var itemsBySeller: [(sellerId: String, items: [CartItem])] {
        Dictionary(grouping: items, by: { $0.product.sellerId })
            .sorted { $0.key < $1.key }
            .map { (sellerId: $0.key, items: $0.value) }
    }

    private var totalCents: Int {
        items.reduce(0) { $0 + ($1.product.priceCents * $1.quantity) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TBTheme.spacingXL) {

                confirmationHeader

                if !items.isEmpty {
                    GlassCard(cornerRadius: 22) {
                        VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                            ForEach(itemsBySeller, id: \.sellerId) { group in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("From \(group.sellerId.replacingOccurrences(of: "seller_", with: "Seller #"))")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(TBTheme.skyBlue)

                                    ForEach(group.items) { item in
                                        HStack {
                                            Text(item.product.name)
                                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                                .foregroundStyle(TBTheme.deepSky)
                                                .lineLimit(1)
                                            Spacer()
                                            Text("\(item.quantity) × \(Money.format(cents: item.product.priceCents))")
                                                .font(.system(size: 14, weight: .medium, design: .rounded))
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
                                Text("Total")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(TBTheme.deepSky)
                                Spacer()
                                Text(Money.format(cents: totalCents))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(TBTheme.icyBlue)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                receiptDetails

                exchangeActions

                policyLinks

                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(PrimaryCTAButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .padding(.top, TBTheme.spacingLG)
        }
        .background(TBTheme.cloudWhite.ignoresSafeArea())
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
            }

            VStack(spacing: 4) {
                Text("Order confirmed!")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                Text("Order #\(orderId)")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var receiptDetails: some View {
        VStack(spacing: 6) {
            Text("A receipt has been emailed to you.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if itemsBySeller.count > 1 {
                Text("Items may ship separately from different sellers.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Text("View order status in the Orders tab.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
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
                if let url = AppConstants.exchangeRequestMailtoURL(orderId: orderId, buyerEmail: buyerEmail) {
                    openURL(url)
                }
            } label: {
                Label("Request an exchange", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(TBTheme.icyBlue)

            Text("We handle changes as exchanges per our policy, not cash refunds.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private var policyLinks: some View {
        HStack(spacing: 16) {
            Button("Exchange policy") { showExchangePolicyBrowser = true }
            Text("·").foregroundStyle(.tertiary)
            Button("Contact support") {
                if let url = AppConstants.supportMailtoURL {
                    openURL(url)
                }
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
    }
}

