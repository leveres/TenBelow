import SwiftUI

struct OrderRowCard: View {
    private enum Metrics {
        static let contentSpacing: CGFloat = 10
        static let thumbnailSize: CGFloat = 34
        static let thumbnailCornerRadius: CGFloat = 9
        static let stackedPreviewSize: CGFloat = 34
    }

    let order: Order
    var products: [Product] = MockData.products

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Metrics.contentSpacing) {

                HStack {
                    Text(order.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    OrderStatusPill(status: order.status)
                }

                if !previewItems.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(previewItems, id: \.id) { item in
                            orderThumbnail(for: item)
                        }
                        if remainingPreviewCount > 0 {
                            Text("+\(remainingPreviewCount)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: Metrics.stackedPreviewSize, height: Metrics.stackedPreviewSize)
                                .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: Metrics.thumbnailCornerRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Metrics.thumbnailCornerRadius)
                                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                                )
                        }
                    }
                }

                Text(primaryTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider().opacity(0.6)

                HStack {
                    Text("Total: \(formatMoney(order.totalCents, order.currency))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 6) {
                        Text("View")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.blue.opacity(0.9))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(orderAccessibilityLabel)
        .accessibilityHint("Opens order details.")
    }

    private var primaryTitle: String {
        let firstItem = order.shipments.first?.items.first?.productName ?? "Order"
        return firstItem
    }

    private var orderItems: [OrderLineItem] {
        order.shipments.flatMap(\.items)
    }

    private var previewItems: [OrderLineItem] {
        Array(orderItems.prefix(3))
    }

    private var remainingPreviewCount: Int {
        max(0, orderItems.count - previewItems.count)
    }

    private var productsById: [String: Product] {
        Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
    }

    private var subtitle: String {
        let date = order.createdAt.formatted(date: .abbreviated, time: .omitted)
        let items = "\(order.totalItemsCount) item" + (order.totalItemsCount == 1 ? "" : "s")
        let shipments = "\(order.shipments.count) shipment" + (order.shipments.count == 1 ? "" : "s")
        return "\(date)  •  \(items)  •  \(shipments)"
    }

    @ViewBuilder
    private func orderThumbnail(for item: OrderLineItem) -> some View {
        if let product = productsById[item.productId] {
            StorefrontImageView(reference: product.primaryImageReference) {
                RoundedRectangle(cornerRadius: Metrics.thumbnailCornerRadius)
                    .fill(Color.white.opacity(0.78))
                    .overlay {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: Metrics.thumbnailSize, height: Metrics.thumbnailSize)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Metrics.thumbnailCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.thumbnailCornerRadius)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 3, y: 1)
        } else {
            RoundedRectangle(cornerRadius: Metrics.thumbnailCornerRadius)
                .fill(Color.white.opacity(0.78))
                .frame(width: Metrics.thumbnailSize, height: Metrics.thumbnailSize)
                .overlay {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.thumbnailCornerRadius)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        }
    }

    private func formatMoney(_ cents: Int, _ currency: String) -> String {
        let value = Decimal(cents) / 100
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    private var orderAccessibilityLabel: String {
        [
            primaryTitle,
            order.status.accessibilityTitle,
            subtitle.replacingOccurrences(of: "•", with: ","),
            "Total \(formatMoney(order.totalCents, order.currency))"
        ].joined(separator: ", ")
    }
}

private extension OrderStatus {
    var accessibilityTitle: String {
        rawValue.replacingOccurrences(of: "-", with: " ")
    }
}
