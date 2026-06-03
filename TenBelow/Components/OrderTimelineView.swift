import SwiftUI

struct OrderTimelineView: View {
    let order: Order

    var body: some View {
        GlassCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Order timeline")
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
        if order.status == .cancelled {
            let cancelledCount = order.shipments.filter { $0.status == .cancelled }.count
            return [
                ("Order placed", order.createdAt.formatted(date: .abbreviated, time: .shortened), true),
                (
                    "Cancelled",
                    "\(cancelledCount) of \(order.shipments.count) shipment\(order.shipments.count == 1 ? "" : "s") cancelled",
                    true
                ),
            ]
        }

        let activeShipments = order.shipments.filter { $0.status != .cancelled }
        let shippedCount = activeShipments.filter { $0.status == .shipped || $0.status == .delivered }.count
        let deliveredCount = activeShipments.filter { $0.status == .delivered }.count
        let shipmentTotal = max(activeShipments.count, 1)

        return [
            ("Order placed", order.createdAt.formatted(date: .abbreviated, time: .shortened), true),
            ("Processing", "Preparing items across sellers", order.status != .placed),
            ("Shipped", "\(shippedCount) of \(shipmentTotal) shipments sent", shippedCount > 0),
            (
                "Delivered",
                "\(deliveredCount) of \(shipmentTotal) shipments delivered",
                deliveredCount == shipmentTotal && !activeShipments.isEmpty
            ),
        ]
    }
}
