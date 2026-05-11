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

    private var activeCount: Int {
        guard let sid = sellerId else {
            return orders.filter { !isCompletedBuyerOrder($0) }.count
        }
        return orders.filter { order in
            let myShipments = order.shipments.filter { $0.sellerId == sid }
            return !myShipments.isEmpty && !myShipments.allSatisfy(isCompletedShipment)
        }.count
    }

    private var completedCount: Int {
        guard let sid = sellerId else {
            return orders.filter(isCompletedBuyerOrder).count
        }
        return orders.filter { order in
            let my = order.shipments.filter { $0.sellerId == sid }
            return !my.isEmpty && my.allSatisfy(isCompletedShipment)
        }.count
    }

    private var totalCents: Int {
        guard let sid = sellerId else {
            return orders.reduce(0) { $0 + $1.totalCents }
        }
        return orders.reduce(0) { sum, order in
            sum + order.shipments
                .filter { $0.sellerId == sid }
                .reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.unitPriceCents * $1.quantity } }
        }
    }

    private var totalLabel: String {
        mode == .seller ? "Earnings" : "Total"
    }

    private func formatMoney(_ cents: Int) -> String {
        let value = Decimal(cents) / 100
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    private func isCompletedBuyerOrder(_ order: Order) -> Bool {
        order.status == .shipped || order.status == .delivered
    }

    private func isCompletedShipment(_ shipment: Shipment) -> Bool {
        shipment.status == .shipped || shipment.status == .delivered
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                chip(icon: "circle.fill", tint: .orange, value: "\(activeCount)", label: "Active", filter: .active)
                chip(icon: "checkmark.circle.fill", tint: .green, value: "\(completedCount)", label: "Done", filter: .completed)
                chip(icon: "dollarsign.circle.fill", tint: TBTheme.icyBlue, value: formatMoney(totalCents), label: totalLabel, filter: .all)
            }

            VStack(spacing: 8) {
                chip(icon: "circle.fill", tint: .orange, value: "\(activeCount)", label: "Active", filter: .active)
                chip(icon: "checkmark.circle.fill", tint: .green, value: "\(completedCount)", label: "Done", filter: .completed)
                chip(icon: "dollarsign.circle.fill", tint: TBTheme.icyBlue, value: formatMoney(totalCents), label: totalLabel, filter: .all)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func chip(icon: String, tint: Color, value: String, label: String, filter: OrderListFilter) -> some View {
        let isSelected = selectedFilter == filter
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            selectedFilter = filter
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                Text("\(value) \(label)")
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? tint.opacity(0.10) : Color.white.opacity(0.76))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.18) : Color.secondary.opacity(0.10), lineWidth: 0.8)
            )
            .foregroundStyle(isSelected ? tint : Color.primary.opacity(0.75))
        }
        .buttonStyle(.plain)
    }
}
