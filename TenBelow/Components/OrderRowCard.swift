import SwiftUI

enum OrderRowCardLayout {
    /// Refined buyer order-history presentation.
    case buyerList
    /// Existing presentation (seller manage-orders list).
    case standard
}

struct OrderRowCard: View {
    private enum Metrics {
        static let cardCornerRadius: CGFloat = 22
        static let productImageSize: CGFloat = 60
        static let buyerProductImageSize: CGFloat = 58
        static let productImageCornerRadius: CGFloat = 16
        static let buyerProductImageCornerRadius: CGFloat = 14
    }

    let order: Order
    var productsById: [String: Product] = [:]
    var hasPendingCancellation: Bool = false
    /// When set, titles/totals/status reflect only this seller's shipments.
    var sellerId: String? = nil
    var layout: OrderRowCardLayout = .buyerList

    var body: some View {
        switch layout {
        case .buyerList:
            buyerListBody
        case .standard:
            standardBody
        }
    }

    // MARK: - Buyer list (compact)

    private var buyerListBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(order.displayOrderNumber)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.52))
                    .lineLimit(1)

                Spacer(minLength: 8)

                compactStatusBadge
            }

            if hasPendingCancellation {
                cancellationBadge
            }

            HStack(alignment: .top, spacing: 12) {
                buyerProductArtwork

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(primaryTitle)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.92))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(formatMoney(displayTotalCents, order.currency))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.88))
                            .multilineTextAlignment(.trailing)
                            .contentTransition(.numericText())
                    }

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.48))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                Text(fulfillmentSummary)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.58))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(buyerCardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.88), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(statusTint.opacity(0.10), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.045), radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(buyerOrderAccessibilityLabel)
        .accessibilityHint("Opens order details.")
    }

    private var compactStatusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.system(size: 8.5, weight: .bold))
                .symbolRenderingMode(.hierarchical)
            Text(statusLabel)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(statusTint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.82), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(statusTint.opacity(0.14), lineWidth: 0.6)
        }
    }

    @ViewBuilder
    private var buyerProductArtwork: some View {
        if let firstItem {
            StorefrontImageView(
                reference: imageReference(for: firstItem),
                loadingPriority: .userInitiated
            ) {
                buyerThumbnailPlaceholder
            }
            .frame(width: Metrics.buyerProductImageSize, height: Metrics.buyerProductImageSize)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Metrics.buyerProductImageCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.buyerProductImageCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1)
            }
        } else {
            buyerThumbnailPlaceholder
        }
    }

    private var buyerThumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: Metrics.buyerProductImageCornerRadius, style: .continuous)
            .fill(thumbnailPlaceholderGradient)
            .frame(width: Metrics.buyerProductImageSize, height: Metrics.buyerProductImageSize)
            .overlay {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky.opacity(0.62))
            }
    }

    private var buyerCardBackground: some View {
        RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.82),
                                TBTheme.skyLight.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
    }

    private var fulfillmentSummary: String {
        switch displayStatus {
        case .placed:
            return sellerId == nil ? "Order received" : "Ready to fulfill"
        case .processing:
            return "Being prepared"
        case .partiallyShipped:
            let sentCount = relevantShipments.filter { shipment in
                shipment.status == .shipped || shipment.status == .delivered
            }.count
            let total = relevantShipments.count
            guard total > 0 else { return "Shipping in progress" }
            let shipmentWord = total == 1 ? "shipment" : "shipments"
            return "\(sentCount) of \(total) \(shipmentWord) sent"
        case .shipped:
            return sellerId == nil ? "Package on the way" : "Shipped — mark delivered when it arrives"
        case .delivered:
            if let deliveredDate = relevantShipments.compactMap(\.deliveredAt).max()
                ?? order.deliveredAt {
                let formatted = deliveredDate.formatted(date: .abbreviated, time: .omitted)
                return "Delivered \(formatted)"
            }
            return "Delivered"
        case .cancelled:
            return "Order cancelled"
        }
    }

    private var buyerOrderAccessibilityLabel: String {
        var parts = [
            order.displayOrderNumber,
            primaryTitle,
            statusLabel,
            fulfillmentSummary,
            subtitle.replacingOccurrences(of: "·", with: ","),
            "Total \(formatMoney(displayTotalCents, order.currency))"
        ]
        if hasPendingCancellation {
            parts.insert("Cancellation requested", at: 2)
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Standard (seller list — unchanged hierarchy)

    private var standardBody: some View {
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

                    Text(formatMoney(displayTotalCents, order.currency))
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
        let firstItem = firstItem?.productName ?? "Order"
        let remainingCount = max(0, orderItems.count - 1)
        return remainingCount == 0 ? firstItem : "\(firstItem) +\(remainingCount) more"
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

    private var displayTotalCents: Int {
        guard sellerId != nil else { return order.totalCents }
        return orderItems.reduce(0) { $0 + ($1.unitPriceCents * $1.quantity) }
    }

    private var displayItemCount: Int {
        guard sellerId != nil else { return order.totalItemsCount }
        return orderItems.reduce(0) { $0 + $1.quantity }
    }

    private var subtitle: String {
        let date = order.createdAt.formatted(date: .abbreviated, time: .omitted)
        let items = "\(displayItemCount) item" + (displayItemCount == 1 ? "" : "s")
        if sellerId != nil {
            if let buyerEmail = order.buyerEmail?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !buyerEmail.isEmpty {
                return "\(date) · \(items) · \(buyerEmail)"
            }
            if let city = order.shipToCity?.trimmingCharacters(in: .whitespacesAndNewlines),
               !city.isEmpty {
                let place = [city, order.shipToState].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                return place.isEmpty ? "\(date) · \(items)" : "\(date) · \(items) · \(place)"
            }
            return "\(date) · \(items)"
        }
        let shipments = "\(order.shipments.count) shipment" + (order.shipments.count == 1 ? "" : "s")
        return "\(date) · \(items) · \(shipments)"
    }

    /// Seller-scoped status when `sellerId` is set; otherwise the order-level status.
    private var displayStatus: OrderStatus {
        guard sellerId != nil else { return order.status }
        let mine = relevantShipments
        guard !mine.isEmpty else { return order.status }
        if mine.allSatisfy({ $0.status == .cancelled }) { return .cancelled }
        if mine.allSatisfy({ $0.status == .delivered }) { return .delivered }
        let hasPreparing = mine.contains { $0.status == .preparing }
        let hasShipped = mine.contains { $0.status == .shipped }
        let hasDelivered = mine.contains { $0.status == .delivered }
        if hasPreparing && (hasShipped || hasDelivered) { return .partiallyShipped }
        if mine.allSatisfy({ $0.status == .shipped || $0.status == .delivered }) { return .shipped }
        if hasPreparing {
            return order.status == .placed ? .placed : .processing
        }
        return order.status
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
            Text(order.displayOrderNumber)
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
        switch displayStatus {
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
        switch displayStatus {
        case .placed: return 0.18
        case .processing: return 0.42
        case .partiallyShipped: return 0.68
        case .shipped: return 0.84
        case .delivered: return 1
        case .cancelled: return 1
        }
    }

    private var progressTitle: String {
        switch displayStatus {
        case .placed: return "Order received"
        case .processing: return "Being prepared"
        case .partiallyShipped: return "Shipping in progress"
        case .shipped: return "On the way"
        case .delivered: return "Delivered"
        case .cancelled: return "Order cancelled"
        }
    }

    private var statusLabel: String {
        switch displayStatus {
        case .placed: return "Order Placed"
        case .processing: return "Processing"
        case .partiallyShipped: return "Partially Shipped"
        case .shipped: return "Shipped"
        case .delivered: return "Delivered"
        case .cancelled: return "Cancelled"
        }
    }

    private var statusIcon: String {
        switch displayStatus {
        case .placed: return "receipt"
        case .processing: return "clock"
        case .partiallyShipped: return "shippingbox.and.arrow.backward"
        case .shipped: return "truck.box"
        case .delivered: return "checkmark.seal"
        case .cancelled: return "xmark.circle"
        }
    }

    private var progressIcon: String {
        switch displayStatus {
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
            "Total \(formatMoney(displayTotalCents, order.currency))"
        ]
        if hasPendingCancellation {
            parts.insert("Cancellation requested", at: 1)
        }
        return parts.joined(separator: ", ")
    }
}
