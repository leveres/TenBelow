import SwiftUI

struct OrderRowCard: View {
    let order: Order

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {

                HStack {
                    Text(order.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    OrderStatusPill(status: order.status)
                }

                Text(primaryTitle)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider().opacity(0.6)

                HStack {
                    Text("Total: \(formatMoney(order.totalCents, order.currency))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 6) {
                        Text("View")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Color.blue.opacity(0.9))
                }
            }
        }
    }

    private var primaryTitle: String {
        let firstItem = order.shipments.first?.items.first?.productName ?? "Order"
        return firstItem
    }

    private var subtitle: String {
        let date = order.createdAt.formatted(date: .abbreviated, time: .omitted)
        let items = "\(order.totalItemsCount) item" + (order.totalItemsCount == 1 ? "" : "s")
        let shipments = "\(order.shipments.count) shipment" + (order.shipments.count == 1 ? "" : "s")
        return "\(date)  •  \(items)  •  \(shipments)"
    }

    private func formatMoney(_ cents: Int, _ currency: String) -> String {
        let value = Decimal(cents) / 100
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
