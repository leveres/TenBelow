import SwiftUI

struct OrderStatusPill: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let status: OrderStatus

    private var label: String {
        switch status {
        case .placed: return "Order Placed"
        case .processing: return "Processing"
        case .partiallyShipped: return "Partially Shipped"
        case .shipped: return "Shipped"
        case .delivered: return "Delivered"
        }
    }

    private var icon: String {
        switch status {
        case .placed: return "receipt"
        case .processing: return "clock"
        case .partiallyShipped: return "shippingbox.and.arrow.backward"
        case .shipped: return "truck.box"
        case .delivered: return "checkmark.seal"
        }
    }

    private var bg: Color {
        switch status {
        case .placed: return .gray.opacity(0.12)
        case .processing: return .blue.opacity(0.12)
        case .partiallyShipped: return .indigo.opacity(0.12)
        case .shipped: return .green.opacity(0.14)
        case .delivered: return .black.opacity(0.06)
        }
    }

    private var fg: Color {
        switch status {
        case .placed: return .secondary
        case .processing: return .blue
        case .partiallyShipped: return .indigo
        case .shipped: return .green
        case .delivered: return .primary.opacity(0.75)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.74))
        .overlay(
            Capsule()
                .strokeBorder(fg.opacity(0.16), lineWidth: 0.8)
        )
        .foregroundStyle(fg)
        .clipShape(Capsule())
    }
}

struct ShipmentStatusPill: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let status: ShipmentStatus

    private var label: String {
        switch status {
        case .preparing: return "Preparing"
        case .shipped: return "Shipped"
        case .delivered: return "Delivered"
        }
    }

    private var icon: String {
        switch status {
        case .preparing: return "clock"
        case .shipped: return "truck.box"
        case .delivered: return "checkmark.seal"
        }
    }

    private var bg: Color {
        switch status {
        case .preparing: return .blue.opacity(0.10)
        case .shipped: return .green.opacity(0.12)
        case .delivered: return .black.opacity(0.06)
        }
    }

    private var fg: Color {
        switch status {
        case .preparing: return .blue
        case .shipped: return .green
        case .delivered: return .primary.opacity(0.75)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.74))
        .overlay(
            Capsule()
                .strokeBorder(fg.opacity(0.16), lineWidth: 0.8)
        )
        .foregroundStyle(fg)
        .clipShape(Capsule())
    }
}
