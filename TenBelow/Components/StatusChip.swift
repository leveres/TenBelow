import SwiftUI

struct StatusChip: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let status: OrderStatus

    private var color: Color {
        switch status {
        case .placed:           return .gray
        case .processing:       return .orange
        case .partiallyShipped: return TBTheme.deepSky
        case .shipped:          return TBTheme.accent
        case .delivered:        return .green
        }
    }

    private var icon: String {
        switch status {
        case .placed:           return "clock"
        case .processing:       return "printer.fill"
        case .partiallyShipped: return "shippingbox"
        case .shipped:          return "box.truck.fill"
        case .delivered:        return "checkmark.circle.fill"
        }
    }

    private var label: String {
        switch status {
        case .placed:           return "Placed"
        case .processing:       return "Processing"
        case .partiallyShipped: return "Partially Shipped"
        case .shipped:          return "Shipped"
        case .delivered:        return "Delivered"
        }
    }

    private var chipOpacity: Double {
        status == .placed ? 0.6 : 1.0
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
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(.white.opacity(0.74))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(color.opacity(0.16), lineWidth: 0.8)
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.03), radius: 8, y: 4)
        .opacity(chipOpacity)
    }
}

#Preview {
    HStack {
        StatusChip(status: .placed)
        StatusChip(status: .processing)
        StatusChip(status: .partiallyShipped)
        StatusChip(status: .shipped)
        StatusChip(status: .delivered)
    }
    .padding()
}
