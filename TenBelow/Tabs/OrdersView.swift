//
//  OrdersView.swift
//  TenBelow
//

import SwiftUI

struct OrdersView: View {
    @AppStorage("userRole") private var userRole = "buyer"
    @AppStorage("sellerSellerId") private var sellerId = ""

    @State private var orders: [Order] = SampleOrders.data
    @State private var selectedFilter: OrderListFilter = .all

    /// Mode is driven by role picked at app start — no segmented control.
    private var mode: OrdersMode {
        userRole == "seller" ? .seller : .buyer
    }

    /// In seller mode with no registered seller, use demo seller for preview.
    private var effectiveSellerId: String {
        if !sellerId.isEmpty { return sellerId }
        return "SELL-01"
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredOrders.isEmpty {
                    emptyState
                } else {
                    ordersList
                }
            }
            .background(Color.blue.opacity(0.03).ignoresSafeArea())
            .navigationTitle("")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            GlassCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 10) {
                        Image("OrdersTitle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 130, height: 56)

                        Text(mode == .buyer
                             ? "Your purchases and delivery updates."
                             : "Manage fulfillment and customer orders.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if mode == .seller, sellerId.isEmpty {
                        Text("Preview: viewing as FilamentFox (SELL-01)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    OrdersStatusBar(
                        orders: [],
                        mode: mode,
                        sellerId: mode == .seller ? effectiveSellerId : nil,
                        selectedFilter: .constant(.all)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            Image(systemName: mode == .buyer ? "cart" : "storefront")
                .font(.system(size: 40))
                .foregroundStyle(TBTheme.skyBlue)

            Text(mode == .buyer ? "No orders yet" : "No orders to fulfill")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)

            Text(mode == .buyer
                 ? "Once you place an order, it'll show up here with live status updates."
                 : sellerId.isEmpty
                    ? "Showing demo data. Add your Seller ID in Settings to see your real orders."
                    : "Orders from your store will appear here when buyers purchase.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ordersList: some View {
        VStack(spacing: 0) {
            GlassCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 10) {
                        Image("OrdersTitle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 130, height: 56)

                        Text(mode == .buyer
                             ? "Your purchases and delivery updates."
                             : "Manage fulfillment and customer orders.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if mode == .seller, sellerId.isEmpty {
                        Text("Preview: viewing as FilamentFox (SELL-01)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    OrdersStatusBar(
                        orders: baseOrders,
                        mode: mode,
                        sellerId: mode == .seller ? effectiveSellerId : nil,
                        selectedFilter: $selectedFilter
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(filteredOrders) { order in
                        NavigationLink {
                            OrderDetailView(
                                order: order,
                                mode: mode,
                                currentSellerId: mode == .seller ? effectiveSellerId : nil
                            )
                        } label: {
                            OrderRowCard(order: order)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
    }

    private var baseOrders: [Order] {
        switch mode {
        case .buyer: return orders
        case .seller:
            return orders.filter { $0.shipments.contains { $0.sellerId == effectiveSellerId } }
        }
    }

    private var filteredOrders: [Order] {
        switch selectedFilter {
        case .all: return baseOrders
        case .active: return baseOrders.filter { $0.status != .delivered }
        case .completed: return baseOrders.filter { $0.status == .delivered }
        }
    }
}


// MARK: - Order Detail View (routes by mode)

struct OrderDetailView: View {
    let order: Order
    let mode: OrdersMode
    /// When seller, only this seller's shipments are shown. Use first shipment's sellerId if nil (e.g. preview).
    var currentSellerId: String?

    var body: some View {
        Group {
            switch mode {
            case .buyer:
                BuyerOrderDetailView(order: order)
            case .seller:
                SellerOrderDetailView(
                    order: order,
                    currentSellerId: currentSellerId ?? order.shipments.first?.sellerId ?? ""
                )
            }
        }
    }
}

// MARK: - Buyer Order Detail (tracking, delivery, receipt)

struct BuyerOrderDetailView: View {
    let order: Order

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {

                GlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your order")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(order.id)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                            OrderStatusPill(status: order.status)
                        }

                        Text(order.createdAt.formatted(date: .long, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("This order ships in \(order.shipments.count) shipment\(order.shipments.count == 1 ? "" : "s") from different sellers.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let city = order.shipToCity, let state = order.shipToState {
                            Label("Delivering to \(city), \(state)", systemImage: "location.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let email = order.buyerEmail {
                            Label("Receipt: \(email)", systemImage: "envelope.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                OrderTimelineView(order: order)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your shipments")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 18)

                    ForEach(order.shipments) { shipment in
                        ShipmentCard(shipment: shipment, mode: .buyer)
                            .padding(.horizontal, 16)
                    }
                }

                GlassCard(cornerRadius: 20) {
                    HStack {
                        Text("Order Total")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatMoney(order.totalCents, order.currency))
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color.blue.opacity(0.03).ignoresSafeArea())
        .navigationTitle("Order details")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func formatMoney(_ cents: Int, _ currency: String) -> String {
        let value = Decimal(cents) / 100
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Seller Order Detail (fulfillment, ship-by, buyer address)

struct SellerOrderDetailView: View {
    let order: Order
    let currentSellerId: String

    private var myShipments: [Shipment] {
        order.shipments.filter { $0.sellerId == currentSellerId }
    }

    private var hasNoShipments: Bool {
        myShipments.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {

                GlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Order to fulfill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(order.id)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                            OrderStatusPill(status: order.status)
                        }

                        Text("Placed \(order.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("You have \(myShipments.count) shipment\(myShipments.count == 1 ? "" : "s") in this order.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let city = order.shipToCity, let state = order.shipToState {
                            Label("Ship to: \(city), \(state)", systemImage: "shippingbox.fill")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary.opacity(0.9))
                        }
                        if let email = order.buyerEmail {
                            Label("Buyer: \(email)", systemImage: "person.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                OrderTimelineView(order: order)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your shipments")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 18)

                    if hasNoShipments {
                        Text("No shipments assigned to you in this order.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(myShipments) { shipment in
                            ShipmentCard(shipment: shipment, mode: .seller)
                                .padding(.horizontal, 16)
                        }
                    }
                }

                GlassCard(cornerRadius: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your total")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatMoney(myShipmentsTotalCents))
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                        Text("Order total: \(formatMoney(order.totalCents, order.currency))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color.blue.opacity(0.03).ignoresSafeArea())
        .navigationTitle("Fulfill order")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var myShipmentsTotalCents: Int {
        myShipments.reduce(0) { sum, s in
            sum + s.items.reduce(0) { $0 + $1.unitPriceCents * $1.quantity }
        }
    }

    private func formatMoney(_ cents: Int, _ currency: String = "USD") -> String {
        let value = Decimal(cents) / 100
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

#Preview {
    OrdersView()
}
