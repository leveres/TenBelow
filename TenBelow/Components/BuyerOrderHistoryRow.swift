import SwiftUI

/// Compact completed-order row for order history (buyer and seller lists).
struct BuyerOrderHistoryRow: View {
    private enum Metrics {
        static let thumbnailSize: CGFloat = 44
        static let cornerRadius: CGFloat = 12
    }

    let order: Order
    var productsById: [String: Product] = [:]
    /// When set, titles/totals/status reflect only this seller's shipments.
    var sellerId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(order.displayOrderNumber)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.48))
                .lineLimit(1)

            HStack(alignment: .center, spacing: 10) {
                thumbnail

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(primaryTitle)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.9))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(formatMoney(displayTotalCents, order.currency))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.82))
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Text(historyMetadata)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.46))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.26))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.62))
        )
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens order details.")
    }

    private var relevantShipments: [Shipment] {
        guard let sellerId else { return order.shipments }
        let trimmed = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return order.shipments }
        return order.shipments.filter { $0.sellerId == trimmed }
    }

    private var orderItems: [OrderLineItem] {
        relevantShipments.flatMap(\.items)
    }

    private var firstItem: OrderLineItem? {
        orderItems.first
    }

    private var primaryTitle: String {
        let firstItem = firstItem?.productName ?? "Order"
        let remainingCount = max(0, orderItems.count - 1)
        return remainingCount == 0 ? firstItem : "\(firstItem) +\(remainingCount) more"
    }

    private var displayTotalCents: Int {
        guard sellerId != nil else { return order.totalCents }
        return orderItems.reduce(0) { $0 + ($1.unitPriceCents * $1.quantity) }
    }

    private var historyMetadata: String {
        let date = (historyDate ?? order.createdAt).formatted(date: .abbreviated, time: .omitted)
        return "\(date) · \(historyStatusLabel)"
    }

    private var historyDate: Date? {
        relevantShipments.compactMap(\.deliveredAt).max()
            ?? order.deliveredAt
            ?? relevantShipments.compactMap(\.shippedAt).max()
    }

    private var historyStatusLabel: String {
        let status = displayStatus
        switch status {
        case .delivered:
            if let deliveredDate = historyDate {
                return "Delivered \(deliveredDate.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Delivered"
        case .cancelled:
            return "Cancelled"
        case .shipped:
            return "Shipped"
        default:
            return "Completed"
        }
    }

    private var displayStatus: OrderStatus {
        guard sellerId != nil else { return order.status }
        let mine = relevantShipments
        guard !mine.isEmpty else { return order.status }
        if mine.allSatisfy({ $0.status == .cancelled }) { return .cancelled }
        if mine.allSatisfy({ $0.status == .delivered }) { return .delivered }
        if mine.allSatisfy({ $0.status == .shipped || $0.status == .delivered }) { return .shipped }
        return order.status
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let firstItem {
            StorefrontImageView(
                reference: imageReference(for: firstItem),
                loadingPriority: .background
            ) {
                thumbnailPlaceholder
            }
            .frame(width: Metrics.thumbnailSize, height: Metrics.thumbnailSize)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.9), TBTheme.skyLight.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: Metrics.thumbnailSize, height: Metrics.thumbnailSize)
            .overlay {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky.opacity(0.55))
            }
    }

    private func imageReference(for item: OrderLineItem) -> String? {
        if let productReference = productsById[item.productId]?.primaryImageReference,
           !productReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return productReference
        }
        return item.thumbnailURL
    }

    private func formatMoney(_ cents: Int, _ currency: String) -> String {
        let value = Decimal(cents) / 100
        return value.formatted(.currency(code: currency))
    }

    private var accessibilityLabel: String {
        [
            order.displayOrderNumber,
            primaryTitle,
            historyMetadata,
            "Total \(formatMoney(displayTotalCents, order.currency))"
        ].joined(separator: ", ")
    }
}
