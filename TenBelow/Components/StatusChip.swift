import SwiftUI

struct StatusChip: View {
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
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))

            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .shadow(color: color.opacity(0.20), radius: 2, y: 1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            ZStack {
                Capsule().fill(color.opacity(0.10))
                Capsule().fill(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), color.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(Capsule())
        .shadow(color: color.opacity(0.12), radius: 3, y: 2)
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
