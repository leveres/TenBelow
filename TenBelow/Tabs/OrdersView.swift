//
//  OrdersView.swift
//  TenBelow
//

import SwiftUI
import AVKit

struct OrdersView: View {
    @EnvironmentObject private var orderStore: OrderStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @AppStorage("userRole") private var userRole = "buyer"
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @AppStorage("sellerSellerId") private var sellerId = ""
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
                if orderStore.isRefreshing, filteredOrders.isEmpty {
                    loadingState
                } else if filteredOrders.isEmpty {
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
            .task(id: "\(mode.rawValue)|\(buyerEmail)|\(sellerId)") {
                await refreshOrders()
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .tint(TBTheme.deepSky)
                .scaleEffect(1.05)
            Text("Loading orders")
                .font(.tbSectionTitle)
                .foregroundStyle(TBTheme.deepSky)
            Text("Pulling in the latest order updates.")
                .font(.tbBody)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            GlassCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 10) {
                        SnowfallTitleContainer(cornerRadius: 22, horizontalPadding: 10, verticalPadding: 8, flakeCount: 72) {
                            Image("OrdersTitle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 160, height: 70)
                        }

                        Text(mode == .buyer
                             ? "Your purchases and delivery updates."
                             : "Manage fulfillment and customer orders.")
                            .font(.tbBody)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if mode == .seller, sellerId.isEmpty {
                        Text("Preview mode: FilamentFox (SELL-01)")
                            .font(.tbCaption)
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
                .font(.tbSectionTitle)
                .foregroundStyle(TBTheme.deepSky)

            Text(emptyStateMessage)
                .font(.tbBody)
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
                        SnowfallTitleContainer(cornerRadius: 22, horizontalPadding: 10, verticalPadding: 8, flakeCount: 72) {
                            Image("OrdersTitle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 160, height: 70)
                        }

                        Text(mode == .buyer
                             ? "Your purchases and delivery updates."
                             : "Manage fulfillment and customer orders.")
                            .font(.tbBody)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if mode == .seller, sellerId.isEmpty {
                        Text("Preview mode: FilamentFox (SELL-01)")
                            .font(.tbCaption)
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
                                orderId: order.id,
                                mode: mode,
                                currentSellerId: mode == .seller ? effectiveSellerId : nil
                            )
                        } label: {
                            OrderRowCard(order: order, products: localProducts.products)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable {
                await refreshOrders()
            }
        }
    }

    private var baseOrders: [Order] {
        switch mode {
        case .buyer: return orderStore.orders
        case .seller:
            return orderStore.orders.filter { $0.shipments.contains { $0.sellerId == effectiveSellerId } }
        }
    }

    private var filteredOrders: [Order] {
        switch selectedFilter {
        case .all: return baseOrders
        case .active: return baseOrders.filter { $0.status != .delivered }
        case .completed: return baseOrders.filter { $0.status == .delivered }
        }
    }

    private var emptyStateMessage: String {
        if let refreshError = orderStore.refreshError {
            return refreshError
        }

        if mode == .buyer {
            return "Your orders will appear here with live status updates."
        }

        if sellerId.isEmpty {
            return "Showing demo data. Add your Seller ID in Settings to view live orders."
        }

        return "Orders from your store will appear here."
    }

    private func refreshOrders() async {
        switch mode {
        case .buyer:
            await orderStore.refreshBuyerOrders(email: buyerEmail)
        case .seller:
            guard !sellerId.isEmpty else { return }
            await orderStore.refreshSellerOrders(sellerId: sellerId)
        }
    }
}


// MARK: - Order Detail View (routes by mode)

struct OrderDetailView: View {
    @EnvironmentObject private var orderStore: OrderStore
    let orderId: String
    let mode: OrdersMode
    /// When seller, only this seller's shipments are shown. Use first shipment's sellerId if nil (e.g. preview).
    var currentSellerId: String?

    var body: some View {
        Group {
            if let order = orderStore.order(withId: orderId) {
                switch mode {
                case .buyer:
                    BuyerOrderDetailView(order: order)
                case .seller:
                    SellerOrderDetailView(
                        order: order,
                        currentSellerId: currentSellerId ?? order.shipments.first?.sellerId ?? ""
                    )
                }
            } else {
                ContentUnavailableView(
                    "Order unavailable",
                    systemImage: "shippingbox",
                    description: Text("This order could not be found.")
                )
            }
        }
    }
}

// MARK: - Buyer Order Detail (tracking, delivery, receipt)

struct BuyerOrderDetailView: View {
    @EnvironmentObject private var localProducts: LocalProductStore
    let order: Order
    @State private var selectedProductionPreview: ProductionPreviewEntry?

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

                if let productionPreview = primaryProductionPreview {
                    GlassCard(cornerRadius: 20) {
                        Button {
                            guard isProductionPreviewUnlocked else { return }
                            selectedProductionPreview = productionPreview
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(0.8))
                                        .frame(width: 48, height: 48)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(TBTheme.skyBlue.opacity(0.16), lineWidth: 1)
                                        )

                                    Image(systemName: isProductionPreviewUnlocked ? "sparkles.tv.fill" : "clock.badge.exclamationmark")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(isProductionPreviewUnlocked ? TBTheme.icyBlue : .secondary)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(isProductionPreviewUnlocked ? "See how your order is being made" : "Production preview not available yet")
                                        .font(.tbBodyStrong)
                                        .foregroundStyle(.primary)

                                    Text(isProductionPreviewUnlocked
                                         ? "Watch a short clip from the creation process"
                                         : "This unlocks once your order reaches processing.")
                                        .font(.tbCaption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isProductionPreviewUnlocked ? TBTheme.icyBlue : Color.secondary.opacity(0.5))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!isProductionPreviewUnlocked)
                        .opacity(isProductionPreviewUnlocked ? 1.0 : 0.62)
                    }
                    .padding(.horizontal, 16)
                }

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
        .sheet(item: $selectedProductionPreview) { preview in
            ProductionPreviewPlayerSheet(preview: preview)
        }
    }

    private var orderLineItems: [OrderLineItem] {
        order.shipments.flatMap(\.items)
    }

    private var productionPreviewEntries: [ProductionPreviewEntry] {
        var seen = Set<String>()
        var entries: [ProductionPreviewEntry] = []

        for item in orderLineItems {
            let resolvedURL = item.productionPreviewResolvedURL ??
                localProducts.product(withId: item.productId)?.productionPreviewURL

            guard let resolvedURL else { continue }

            let dedupeKey = "\(item.productId)|\(resolvedURL.absoluteString)"
            guard seen.insert(dedupeKey).inserted else { continue }

            entries.append(
                ProductionPreviewEntry(
                    productId: item.productId,
                    productName: item.productName,
                    videoURL: resolvedURL
                )
            )
        }

        return entries
    }

    private var primaryProductionPreview: ProductionPreviewEntry? {
        productionPreviewEntries.first
    }

    private var isProductionPreviewUnlocked: Bool {
        if order.status != .placed {
            return true
        }

        // Some orders may still be marked "placed" while an individual shipment has started preparing.
        return order.shipments.contains { shipment in
            switch shipment.status {
            case .preparing, .shipped, .delivered:
                return true
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

private struct ProductionPreviewEntry: Identifiable {
    let productId: String
    let productName: String
    let videoURL: URL

    var id: String {
        "\(productId)|\(videoURL.absoluteString)"
    }
}

private struct ProductionPreviewPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preview: ProductionPreviewEntry

    var body: some View {
        NavigationStack {
            VideoPlayer(player: AVPlayer(url: preview.videoURL))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Production Preview")
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - Seller Order Detail (fulfillment, ship-by, buyer address)

struct SellerOrderDetailView: View {
    @EnvironmentObject private var orderStore: OrderStore
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
                            Label("Buyer: \(email)", systemImage: "person")
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
                            VStack(alignment: .leading, spacing: 8) {
                                ShipmentCard(shipment: shipment, mode: .seller)

                                if let nextAction = orderStore.nextAction(for: shipment, order: order) {
                                    Button {
                                        Task {
                                            await orderStore.performShipmentAction(
                                                nextAction,
                                                orderId: order.id,
                                                shipmentId: shipment.id,
                                                sellerId: currentSellerId
                                            )
                                        }
                                    } label: {
                                        Label(nextAction.buttonTitle, systemImage: actionIcon(for: nextAction))
                                            .font(.tbBodyStrong)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true, horizontalPadding: 20, verticalPadding: 12, fontSize: 15))
                                }
                            }
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

    private func actionIcon(for action: SellerShipmentAction) -> String {
        switch action {
        case .startProcessing:
            return "gearshape.2.fill"
        case .markShipped:
            return "truck.box.fill"
        case .markDelivered:
            return "checkmark.circle.fill"
        }
    }
}

#Preview {
    OrdersView()
}
