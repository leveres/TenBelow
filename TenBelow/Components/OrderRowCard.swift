import SwiftUI

struct OrderRowCard: View {
    private enum Metrics {
        static let contentSpacing: CGFloat = 5
        static let thumbnailSize: CGFloat = 27
        static let thumbnailCornerRadius: CGFloat = 7
        static let stackedPreviewSize: CGFloat = 27
    }

    let order: Order
    var productsById: [String: Product] = [:]
    var hasPendingCancellation: Bool = false

    var body: some View {
        GlassCard(borderStyle: .accent, contentPadding: 10) {
            VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                HStack(alignment: .center) {
                    Text(order.id)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 138 / 255, green: 155 / 255, blue: 176 / 255))
                    Spacer()
                    statusBadge
                }

                if hasPendingCancellation {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Cancellation requested")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.10), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.8)
                    )
                }

                if !previewItems.isEmpty {
                    HStack(spacing: 7) {
                        ForEach(previewItems, id: \.id) { item in
                            orderThumbnail(for: item)
                        }
                        if remainingPreviewCount > 0 {
                            Text("+\(remainingPreviewCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(TBTheme.deepSky.opacity(0.72))
                                .frame(width: Metrics.stackedPreviewSize, height: Metrics.stackedPreviewSize)
                                .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: Metrics.thumbnailCornerRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Metrics.thumbnailCornerRadius, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.86), lineWidth: 1)
                                )
                        }
                    }
                }

                Text(primaryTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.productNameTitleGradient)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 138 / 255, green: 155 / 255, blue: 176 / 255))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Divider()
                    .opacity(0.35)

                HStack(alignment: .center) {
                    Text("Total: \(formatMoney(order.totalCents, order.currency))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky.opacity(0.68))
                    Spacer()
                    HStack(spacing: 4) {
                        Text("View")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(TBTheme.icyBlue)
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        TBTheme.skyLight.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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

    private var firstItem: OrderLineItem? {
        orderItems.first
    }

    private var previewItems: [OrderLineItem] {
        Array(orderItems.prefix(3))
    }

    private var remainingPreviewCount: Int {
        max(0, orderItems.count - previewItems.count)
    }

    private var subtitle: String {
        let date = order.createdAt.formatted(date: .abbreviated, time: .omitted)
        let items = "\(order.totalItemsCount) item" + (order.totalItemsCount == 1 ? "" : "s")
        let shipments = "\(order.shipments.count) shipment" + (order.shipments.count == 1 ? "" : "s")
        return "\(date)  •  \(items)  •  \(shipments)"
    }

    @ViewBuilder
    private var statusBadge: some View {
        OrderStatusPill(status: order.status)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.8)
            )
    }

    @ViewBuilder
    private func orderThumbnail(for item: OrderLineItem) -> some View {
        if let product = productsById[item.productId] {
            StorefrontImageView(
                reference: product.primaryImageReference,
                loadingPriority: .userInitiated
            ) {
                RoundedRectangle(cornerRadius: Metrics.thumbnailCornerRadius)
                    .fill(thumbnailPlaceholderGradient)
                    .overlay {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(TBTheme.deepSky.opacity(0.74))
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
                .fill(thumbnailPlaceholderGradient)
                .frame(width: Metrics.thumbnailSize, height: Metrics.thumbnailSize)
                .overlay {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(TBTheme.deepSky.opacity(0.74))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.thumbnailCornerRadius)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1)
                )
        }
    }

    private var thumbnailPlaceholderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.88),
                TBTheme.skyLight.opacity(0.46),
                TBTheme.frostGlow.opacity(0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func formatMoney(_ cents: Int, _ currency: String) -> String {
        let value = Decimal(cents) / 100
        return value.formatted(.currency(code: currency))
    }

    private var orderAccessibilityLabel: String {
        var parts = [
            primaryTitle,
            order.status.accessibilityTitle,
            subtitle.replacingOccurrences(of: "•", with: ","),
            "Total \(formatMoney(order.totalCents, order.currency))"
        ]
        if hasPendingCancellation {
            parts.insert("Cancellation requested", at: 1)
        }
        return parts.joined(separator: ", ")
    }
}

private extension OrderStatus {
    var accessibilityTitle: String {
        rawValue.replacingOccurrences(of: "-", with: " ")
    }
}
