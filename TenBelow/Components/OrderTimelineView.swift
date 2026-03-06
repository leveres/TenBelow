import SwiftUI

struct OrderTimelineView: View {
    let order: Order

    var body: some View {
        GlassCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Order Progress")
                    .font(.headline)
                    .fontWeight(.semibold)

                ForEach(steps, id: \.title) { step in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(step.isComplete ? Color.green : Color.secondary.opacity(0.35))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if let subtitle = step.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                }
            }
        }
    }

    private var steps: [(title: String, subtitle: String?, isComplete: Bool)] {
        let shippedCount = order.shipments.filter { $0.status == .shipped || $0.status == .delivered }.count
        let deliveredCount = order.shipments.filter { $0.status == .delivered }.count

        return [
            ("Order Placed", order.createdAt.formatted(date: .abbreviated, time: .shortened), true),
            ("Processing", "Preparing items across sellers", order.status != .placed),
            ("Shipped", "\(shippedCount) of \(order.shipments.count) shipments sent", shippedCount > 0),
            ("Delivered", "\(deliveredCount) of \(order.shipments.count) shipments delivered", deliveredCount == order.shipments.count && order.shipments.count > 0)
        ]
    }
}
