//
//  OrdersStatusBar.swift
//  TenBelow
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

enum OrderListFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"
}

struct OrdersStatusBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let orders: [Order]
    var mode: OrdersMode = .buyer
    var sellerId: String? = nil
    @Binding var selectedFilter: OrderListFilter

#if os(iOS)
    private enum Haptics {
        static let chipTap = UIImpactFeedbackGenerator(style: .light)
    }
#endif

    private struct Summary {
        var activeCount = 0
        var completedCount = 0
        var totalCents = 0
    }

    private var summary: Summary {
        guard let sid = sellerId else {
            return orders.reduce(into: Summary()) { partial, order in
                partial.totalCents += order.totalCents
                if isCompletedBuyerOrder(order) {
                    partial.completedCount += 1
                } else {
                    partial.activeCount += 1
                }
            }
        }

        return orders.reduce(into: Summary()) { partial, order in
            var shipmentSubtotal = 0
            var sellerShipmentCount = 0
            var sellerCompletedShipmentCount = 0

            for shipment in order.shipments where shipment.sellerId == sid {
                sellerShipmentCount += 1
                if isCompletedShipment(shipment) {
                    sellerCompletedShipmentCount += 1
                }
                shipmentSubtotal += shipment.items.reduce(0) { $0 + $1.unitPriceCents * $1.quantity }
            }

            guard sellerShipmentCount > 0 else { return }
            partial.totalCents += shipmentSubtotal
            if sellerCompletedShipmentCount == sellerShipmentCount {
                partial.completedCount += 1
            } else {
                partial.activeCount += 1
            }
        }
    }

    private var totalLabel: String {
        mode == .seller ? "Earnings" : "Total"
    }

    private func formatMoney(_ cents: Int) -> String {
        let value = Decimal(cents) / 100
        return value.formatted(.currency(code: "USD"))
    }

    private func isCompletedBuyerOrder(_ order: Order) -> Bool {
        order.status == .shipped || order.status == .delivered || order.status == .cancelled
    }

    private func isCompletedShipment(_ shipment: Shipment) -> Bool {
        shipment.status == .shipped || shipment.status == .delivered || shipment.status == .cancelled
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    chip(icon: "circle.fill", tint: .orange, value: "\(summary.activeCount)", label: "Active", filter: .active)
                    chip(icon: "checkmark.circle.fill", tint: .green, value: "\(summary.completedCount)", label: "Done", filter: .completed)
                    chip(icon: "dollarsign.circle.fill", tint: TBTheme.icyBlue, value: formatMoney(summary.totalCents), label: totalLabel, filter: .all)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chip(icon: "circle.fill", tint: .orange, value: "\(summary.activeCount)", label: "Active", filter: .active)
                            chip(icon: "checkmark.circle.fill", tint: .green, value: "\(summary.completedCount)", label: "Done", filter: .completed)
                            chip(icon: "dollarsign.circle.fill", tint: TBTheme.icyBlue, value: formatMoney(summary.totalCents), label: totalLabel, filter: .all)
                        }
                        .frame(minWidth: proxy.size.width, alignment: .center)
                    }
                }
                .frame(height: 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .animation(nil, value: selectedFilter)
    }

    private func chip(icon: String, tint: Color, value: String, label: String, filter: OrderListFilter) -> some View {
        let isSelected = selectedFilter == filter
        return Button {
            #if os(iOS)
            Haptics.chipTap.prepare()
            Haptics.chipTap.impactOccurred(intensity: 0.75)
            #endif
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedFilter = filter
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: 14, height: 14)

                Text("\(value) \(label)")
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minHeight: 18, alignment: .center)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.76))
            )
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.10))
                    .opacity(isSelected ? 1 : 0)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.10), lineWidth: 0.8)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.18), lineWidth: 0.8)
                    .opacity(isSelected ? 1 : 0)
            )
            .foregroundStyle(isSelected ? tint : Color.primary.opacity(0.75))
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Capsule(style: .continuous))
            .transaction { $0.disablesAnimations = true }
            .animation(nil, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        #if os(iOS)
        .onAppear {
            Haptics.chipTap.prepare()
        }
        #endif
    }
}
