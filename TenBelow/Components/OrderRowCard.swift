import SwiftUI

struct OrderRowCard: View {
    private enum Metrics {
        static let cardCornerRadius: CGFloat = 22
        static let productImageSize: CGFloat = 60
        static let productImageCornerRadius: CGFloat = 16
    }

    let order: Order
    var productsById: [String: Product] = [:]
    var hasPendingCancellation: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                orderNumberBadge
                Spacer(minLength: 8)
                statusBadge
            }

            if hasPendingCancellation {
                cancellationBadge
            }

            HStack(spacing: 13) {
                primaryProductArtwork

                VStack(alignment: .leading, spacing: 5) {
                    Text(primaryTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.productNameTitleGradient)
                        .lineLimit(2)

                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.56))
                        .lineLimit(2)

                    Text(formatMoney(order.totalCents, order.currency))
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            progressFooter
        }
        .padding(12)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(cardBorderGradient, lineWidth: 1.2)
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))
        .shadow(color: statusTint.opacity(0.08), radius: 13, y: 6)
        .shadow(color: Color.black.opacity(0.055), radius: 7, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(orderAccessibilityLabel)
        .accessibilityHint("Opens order details.")
    }

    private var primaryTitle: String {
        let firstItem = order.shipments.first?.items.first?.productName ?? "Order"
        let remainingCount = max(0, orderItems.count - 1)
        return remainingCount == 0 ? firstItem : "\(firstItem) +\(remainingCount) more"
    }

    private var orderItems: [OrderLineItem] {
        order.shipments.flatMap(\.items)
    }

    private var firstItem: OrderLineItem? {
        orderItems.first
    }

    private var subtitle: String {
        let date = order.createdAt.formatted(date: .abbreviated, time: .omitted)
        let items = "\(order.totalItemsCount) item" + (order.totalItemsCount == 1 ? "" : "s")
        let shipments = "\(order.shipments.count) shipment" + (order.shipments.count == 1 ? "" : "s")
        return "\(date) · \(items) · \(shipments)"
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: statusIcon)
                .font(.system(size: 9.5, weight: .bold))
                .symbolRenderingMode(.hierarchical)
            Text(statusLabel)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(statusTint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.78), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(statusTint.opacity(0.18), lineWidth: 0.8)
        }
    }

    private var orderNumberBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "bag.fill")
                .font(.system(size: 9, weight: .bold))
            Text(order.id)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(TBTheme.deepSky.opacity(0.78))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(TBTheme.skyLight.opacity(0.42), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.82), lineWidth: 0.8)
        }
    }

    private var cancellationBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("Cancellation requested")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.10), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.orange.opacity(0.15), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var primaryProductArtwork: some View {
        if let firstItem {
            StorefrontImageView(
                reference: imageReference(for: firstItem),
                loadingPriority: .userInitiated
            ) {
                RoundedRectangle(cornerRadius: Metrics.productImageCornerRadius, style: .continuous)
                    .fill(thumbnailPlaceholderGradient)
                    .overlay {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(TBTheme.deepSky.opacity(0.74))
                    }
            }
            .frame(width: Metrics.productImageSize, height: Metrics.productImageSize)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Metrics.productImageCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.productImageCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.3)
            }
            .shadow(color: statusTint.opacity(0.16), radius: 8, y: 4)
        } else {
            RoundedRectangle(cornerRadius: Metrics.productImageCornerRadius, style: .continuous)
                .fill(thumbnailPlaceholderGradient)
                .frame(width: Metrics.productImageSize, height: Metrics.productImageSize)
                .overlay {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(TBTheme.deepSky.opacity(0.74))
                }
        }
    }

    private var progressFooter: some View {
        VStack(spacing: 6) {
            HStack {
                Label(progressTitle, systemImage: progressIcon)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusTint)
                Spacer()
                HStack(spacing: 4) {
                    Text("View order")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                }
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky.opacity(0.72))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(TBTheme.skyLight.opacity(0.55))

                    Capsule(style: .continuous)
                        .fill(statusAccentGradient)
                        .frame(width: proxy.size.width * progressValue)
                }
            }
            .frame(height: 4)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.68),
                                statusTint.opacity(0.035),
                                TBTheme.skyLight.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
    }

    private var cardBorderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.95),
                statusTint.opacity(0.30),
                TBTheme.deepSky.opacity(0.13)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var statusAccentGradient: LinearGradient {
        LinearGradient(
            colors: [statusTint.opacity(0.72), statusTint],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var statusTint: Color {
        switch order.status {
        case .placed:
            return Color(red: 0.44, green: 0.54, blue: 0.66)
        case .processing:
            return TBTheme.icyBlue
        case .partiallyShipped:
            return .indigo
        case .shipped:
            return .green
        case .delivered:
            return TBTheme.deepSky
        case .cancelled:
            return .red
        }
    }

    private var progressValue: CGFloat {
        switch order.status {
        case .placed: return 0.18
        case .processing: return 0.42
        case .partiallyShipped: return 0.68
        case .shipped: return 0.84
        case .delivered: return 1
        case .cancelled: return 1
        }
    }

    private var progressTitle: String {
        switch order.status {
        case .placed: return "Order received"
        case .processing: return "Being prepared"
        case .partiallyShipped: return "Shipping in progress"
        case .shipped: return "On the way"
        case .delivered: return "Delivered"
        case .cancelled: return "Order cancelled"
        }
    }

    private var statusLabel: String {
        switch order.status {
        case .placed: return "Order Placed"
        case .processing: return "Processing"
        case .partiallyShipped: return "Partially Shipped"
        case .shipped: return "Shipped"
        case .delivered: return "Delivered"
        case .cancelled: return "Cancelled"
        }
    }

    private var statusIcon: String {
        switch order.status {
        case .placed: return "receipt"
        case .processing: return "clock"
        case .partiallyShipped: return "shippingbox.and.arrow.backward"
        case .shipped: return "truck.box"
        case .delivered: return "checkmark.seal"
        case .cancelled: return "xmark.circle"
        }
    }

    private var progressIcon: String {
        switch order.status {
        case .placed: return "checkmark.circle.fill"
        case .processing: return "gearshape.2.fill"
        case .partiallyShipped: return "shippingbox.fill"
        case .shipped: return "truck.box.fill"
        case .delivered: return "checkmark.seal.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    private func imageReference(for item: OrderLineItem) -> String? {
        if let productReference = productsById[item.productId]?.primaryImageReference,
           !productReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return productReference
        }
        return item.thumbnailURL
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
            statusLabel,
            progressTitle,
            subtitle.replacingOccurrences(of: "•", with: ","),
            "Total \(formatMoney(order.totalCents, order.currency))"
        ]
        if hasPendingCancellation {
            parts.insert("Cancellation requested", at: 1)
        }
        return parts.joined(separator: ", ")
    }
}
