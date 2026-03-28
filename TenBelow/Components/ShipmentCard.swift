import SwiftUI

struct ShipmentCard: View {
    let shipment: Shipment
    let mode: OrdersMode

    var body: some View {
        GlassCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(shipment.sellerName)
                            .font(.headline)
                            .fontWeight(.semibold)

                        if let handle = shipment.sellerHandle, !handle.isEmpty {
                            Text(handle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    ShipmentStatusPill(status: shipment.status)
                }

                if mode == .buyer {
                    buyerLine
                } else {
                    sellerLine
                }

                Divider().opacity(0.6)

                VStack(spacing: 10) {
                    ForEach(shipment.items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.productName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Qty \(item.quantity)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatMoney(item.unitPriceCents * item.quantity, "USD"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var buyerLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let carrier = shipment.carrier, let tracking = shipment.trackingNumber, !tracking.isEmpty {
                Text("\(carrier) • \(tracking)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if shipment.status == .preparing {
                Text("Preparing shipment")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let shipBy = shipment.shipByDate {
                Text("Estimated ship by \(shipBy.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sellerLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let shipBy = shipment.shipByDate {
                Text("Ship by \(shipBy.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary.opacity(0.85))
            } else {
                Text("Ship by: Not set")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if shipment.status == .preparing {
                Text("Next: purchase label and add tracking")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatMoney(_ cents: Int, _ currency: String) -> String {
        let value = Decimal(cents) / 100
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
