//
//  OrdersView.swift
//  TenBelow
//

import SwiftUI
import AVKit
#if os(iOS)
import PhotosUI
import UIKit
import UniformTypeIdentifiers
#endif

struct OrdersView: View {
    private enum PlaceholderSeller {
        static let id = "SELL-01"
        static let name = "FilamentFox"
    }

    private enum HeroMetrics {
        static let titleImageHeight: CGFloat = 88
        static let titleImageScale: CGFloat = 1.22
        static let snowfallCornerRadius: CGFloat = 18
        static let snowfallHorizontalPadding: CGFloat = 10
        static let snowfallVerticalPadding: CGFloat = 8
        static let snowfallFlakeCount: Int = 56
        static let headerSpacing: CGFloat = 3
    }

    @EnvironmentObject private var orderStore: OrderStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @AppStorage("userRole") private var userRole = "buyer"
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @AppStorage("sellerSellerId") private var sellerId = ""
    @State private var selectedFilter: OrderListFilter = .all
    @State private var lastOrdersRefresh = Date.distantPast

    /// Mode is driven by role picked at app start — no segmented control.
    private var mode: OrdersMode {
        userRole == "seller" ? .seller : .buyer
    }

    /// In seller mode with no registered seller, status uses a placeholder seller id.
    private var effectiveSellerId: String {
        if !sellerId.isEmpty { return sellerId }
        return PlaceholderSeller.id
    }

    var body: some View {
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
        VStack(spacing: 0) {
            ordersHeaderBlock(statusBarOrders: [], filterBinding: .constant(.all))

            ScrollView {
                VStack(spacing: 10) {
                    Text(mode == .buyer ? "No orders yet" : "No orders to fulfill")
                        .font(.tbSectionTitle)
                        .foregroundStyle(TBTheme.deepSky)

                    Text(emptyStateMessage)
                        .font(.tbBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .accessibilityIdentifier("orders.empty.scroll")
            .refreshable {
                await refreshOrders(force: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ordersList: some View {
        VStack(spacing: 0) {
            ordersHeaderBlock(statusBarOrders: baseOrders, filterBinding: $selectedFilter)

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
                        .accessibilityIdentifier("orders.row.\(order.id)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable {
                await refreshOrders(force: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ordersHeaderBlock(
        statusBarOrders: [Order],
        filterBinding: Binding<OrderListFilter>
    ) -> some View {
        GlassCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: HeroMetrics.headerSpacing) {
                    SnowfallTitleContainer(
                        cornerRadius: HeroMetrics.snowfallCornerRadius,
                        horizontalPadding: HeroMetrics.snowfallHorizontalPadding,
                        verticalPadding: HeroMetrics.snowfallVerticalPadding,
                        flakeCount: HeroMetrics.snowfallFlakeCount,
                        effectHorizontalInset: 14,
                        effectVerticalInset: 12
                    ) {
                        Image("OrdersTitle")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: HeroMetrics.titleImageHeight)
                            .scaleEffect(HeroMetrics.titleImageScale)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(mode == .buyer
                         ? "Your purchases and delivery updates."
                         : "Manage fulfillment and customer orders.")
                        .font(.tbBody)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                #if DEBUG
                if mode == .seller, sellerId.isEmpty {
                    Text("Preview mode: \(PlaceholderSeller.name) (\(PlaceholderSeller.id))")
                        .font(.tbCaption)
                        .foregroundStyle(.tertiary)
                }
                #endif

                OrdersStatusBar(
                    orders: statusBarOrders,
                    mode: mode,
                    sellerId: mode == .seller ? effectiveSellerId : nil,
                    selectedFilter: filterBinding
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var baseOrders: [Order] {
        switch mode {
        case .buyer: return orderStore.orders
        case .seller:
            return orderStore.orders.filter { $0.shipments.contains { $0.sellerId == effectiveSellerId } }
        }
    }

    private var filteredOrders: [Order] {
        filtered(baseOrders, for: selectedFilter)
    }

    private var emptyStateMessage: String {
        if let refreshError = orderStore.refreshError {
            return refreshError
        }

        if mode == .buyer {
            return "Your orders will appear here with live status updates."
        }

        if sellerId.isEmpty {
            #if DEBUG
            return "Showing demo data. Add your Seller ID in Settings to view live orders."
            #else
            return "Enter your Seller ID in Settings to load orders for your store."
            #endif
        }

        return "Orders from your store will appear here."
    }

    private func filtered(_ orders: [Order], for filter: OrderListFilter) -> [Order] {
        switch filter {
        case .all:
            return orders
        case .active:
            return orders.filter { !isCompletedForCurrentMode($0) }
        case .completed:
            return orders.filter(isCompletedForCurrentMode)
        }
    }

    private func isCompletedForCurrentMode(_ order: Order) -> Bool {
        switch mode {
        case .buyer:
            return order.status == .shipped || order.status == .delivered
        case .seller:
            let myShipments = order.shipments.filter { $0.sellerId == effectiveSellerId }
            guard !myShipments.isEmpty else { return false }
            return myShipments.allSatisfy { $0.status == .shipped || $0.status == .delivered }
        }
    }

    private func refreshOrders(force: Bool = false) async {
        let now = Date()
        guard force || now.timeIntervalSince(lastOrdersRefresh) > 45 else { return }
        lastOrdersRefresh = now

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
    var fallbackOrder: Order? = nil

    var body: some View {
        Group {
            if let order = orderStore.order(withId: orderId) ?? fallbackOrder {
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

private enum BuyerExchangeSheet: Identifiable {
    case request
    case status(String)

    var id: String {
        switch self {
        case .request:
            return "request"
        case .status(let requestId):
            return "status-\(requestId)"
        }
    }
}

struct BuyerOrderDetailView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var exchangeStore: ExchangeStore
    @EnvironmentObject private var localProducts: LocalProductStore
    let order: Order
    @State private var selectedProductionPreview: ProductionPreviewEntry?
    @State private var exchangeSheet: BuyerExchangeSheet?
    @State private var showExchangePolicyBrowser = false

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

                if !productionPreviewEntries.isEmpty {
                    productionPreviewSection
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

                buyerExchangeSection
                    .padding(.horizontal, 16)

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
        .sheet(item: $exchangeSheet) { sheet in
            switch sheet {
            case .request:
                ExchangeRequestFlowSheet(
                    order: order,
                    items: exchangeEligibleItemContexts
                )
                .environmentObject(exchangeStore)
                .environmentObject(catalog)
            case .status(let requestId):
                NavigationStack {
                    ExchangeStatusScreen(exchangeRequestId: requestId)
                        .environmentObject(exchangeStore)
                }
            }
        }
        .sheet(isPresented: $showExchangePolicyBrowser) {
            LegalDocumentSheet(document: .exchangePolicy)
        }
        .task(id: order.id) {
            _ = try? await exchangeStore.refreshRequests(for: order.id)
        }
    }

    private var buyerExchangeSection: some View {
        GlassCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Exchanges")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("All sales are final. Eligible orders may request a one-time exchange for the same item if it arrived damaged, defective, incorrect, or materially flawed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let latestExchangeRequest {
                    GlassCard(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            ExchangeStatusPill(status: latestExchangeRequest.status)

                            Text(latestExchangeRequest.productTitle)
                                .font(.tbBodyStrong)
                                .foregroundStyle(TBTheme.deepSky)

                            Text(latestExchangeRequest.status.detailCopy)
                                .font(.tbCaption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                exchangeSheet = .status(latestExchangeRequest.id)
                            } label: {
                                Text("Track Request")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .tint(TBTheme.icyBlue)
                        }
                    }
                }

                Button {
                    showExchangePolicyBrowser = true
                } label: {
                    Text("Read Exchange Policy")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(TBTheme.icyBlue)

                if !exchangeEligibleItemContexts.isEmpty {
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        exchangeSheet = .request
                    } label: {
                        Label("Request an Exchange", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TBTheme.icyBlue)
                } else {
                    Text(exchangeSectionUnavailableCopy)
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var latestExchangeRequest: ExchangeRequest? {
        exchangeStore.requests(for: order.id).first
    }

    private var exchangeItemContexts: [ExchangeOrderItemContext] {
        order.shipments.flatMap { shipment in
            shipment.items.map { item in
                ExchangeOrderItemContext(
                    orderId: order.id,
                    shipmentId: shipment.id,
                    sellerId: shipment.sellerId,
                    sellerName: shipment.sellerName,
                    item: item
                )
            }
        }
    }

    private var exchangeEligibleItemContexts: [ExchangeOrderItemContext] {
        exchangeItemContexts.filter { context in
            let item = context.item
            let exchangeCount = item.exchangeCount ?? 0
            let hasActiveExchange = (item.hasExchangeRequest ?? false) && exchangeCount < catalog.config.maxExchangeCountPerOrderItem
            let isDelivered = item.deliveredAt != nil || item.fulfillmentStatus == .delivered
            let withinWindow: Bool = {
                guard let exchangeEligibleUntil = item.exchangeEligibleUntil else { return true }
                return exchangeEligibleUntil >= .now
            }()
            return isDelivered && withinWindow && !hasActiveExchange && exchangeCount < catalog.config.maxExchangeCountPerOrderItem
        }
    }

    private var exchangeSectionUnavailableCopy: String {
        if exchangeItemContexts.allSatisfy({ $0.item.deliveredAt == nil && $0.item.fulfillmentStatus != .delivered }) {
            return "Exchanges can be requested after delivery."
        }
        if exchangeItemContexts.allSatisfy({ ($0.item.exchangeCount ?? 0) >= catalog.config.maxExchangeCountPerOrderItem }) {
            return "This order has already used its one-time exchange."
        }
        return "Exchange eligibility is not available for this order right now."
    }

    private var orderLineItems: [OrderLineItem] {
        order.shipments.flatMap(\.items)
    }

    private var productionPreviewEntries: [ProductionPreviewEntry] {
        var seen = Set<String>()
        var entries: [ProductionPreviewEntry] = []

        for item in orderLineItems {
            let resolvedURL = item.productionPreviewResolvedURL

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

    private func formatMoney(_ cents: Int, _ currency: String) -> String {
        let value = Decimal(cents) / 100
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    private var productionPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("See your item being made")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal, 2)

            ForEach(productionPreviewEntries) { preview in
                GlassCard(cornerRadius: 20) {
                    Button {
                        selectedProductionPreview = preview
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

                                Image(systemName: "sparkles.tv.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(TBTheme.icyBlue)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(preview.productName)
                                    .font(.tbBodyStrong)
                                    .foregroundStyle(.primary)

                                Text("Watch the maker video for this item.")
                                    .font(.tbCaption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TBTheme.icyBlue)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
    @State private var displayedOrder: Order
    @State private var pendingShipmentDraft: ShipmentTrackingDraft?
    @State private var isShowingProductionPreviewPicker = false
    @State private var activeProductionPreviewTarget: SellerProductionPreviewTarget?
    @State private var selectedProductionPreviewEntry: ProductionPreviewEntry?
    @State private var productionPreviewBusyItemIDs: Set<String> = []
    @State private var carrier = ""
    @State private var trackingNumber = ""

    init(order: Order, currentSellerId: String) {
        self.order = order
        self.currentSellerId = currentSellerId
        _displayedOrder = State(initialValue: order)
    }

    private var isPreviewOrder: Bool {
        orderStore.order(withId: order.id) == nil
    }

    private var myShipments: [Shipment] {
        displayedOrder.shipments.filter { $0.sellerId == currentSellerId }
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
                            OrderStatusPill(status: displayedOrder.status)
                        }

                        Text("Placed \(displayedOrder.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("You have \(myShipments.count) shipment\(myShipments.count == 1 ? "" : "s") in this order.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let city = displayedOrder.shipToCity, let state = displayedOrder.shipToState {
                            Label("Ship to: \(city), \(state)", systemImage: "shippingbox.fill")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary.opacity(0.9))
                        }
                        if let email = displayedOrder.buyerEmail {
                            Label("Buyer: \(email)", systemImage: "person")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                OrderTimelineView(order: displayedOrder)
                    .padding(.horizontal, 16)

                if !isPreviewOrder, let shipmentActionError = orderStore.shipmentActionError, !shipmentActionError.isEmpty {
                    Text(shipmentActionError)
                        .font(.tbCaption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }

                if let productionPreviewActionError = orderStore.productionPreviewActionError, !productionPreviewActionError.isEmpty {
                    Text(productionPreviewActionError)
                        .font(.tbCaption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }

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
                                sellerFulfillmentWorkspace(for: shipment)

                                if let nextAction = orderStore.nextAction(for: shipment, order: displayedOrder) {
                                    Button {
                                        handleShipmentAction(nextAction, for: shipment)
                                    } label: {
                                        Label(actionTitle(for: nextAction), systemImage: actionIcon(for: nextAction))
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
                        Text("Order total: \(formatMoney(displayedOrder.totalCents, displayedOrder.currency))")
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
        .onChange(of: order) { _, newOrder in
            if !isPreviewOrder {
                displayedOrder = newOrder
            }
        }
        .sheet(item: $pendingShipmentDraft) { draft in
            ShipmentTrackingSheet(
                sellerName: draft.sellerName,
                carrier: $carrier,
                trackingNumber: $trackingNumber,
                onCancel: {
                    pendingShipmentDraft = nil
                },
                onSave: {
                    let trimmedCarrier = carrier.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedTrackingNumber = trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedCarrier.isEmpty, !trimmedTrackingNumber.isEmpty else { return }

                    Task {
                        if isPreviewOrder {
                            applyPreviewShipmentAction(
                                .markShipped,
                                shipmentId: draft.shipmentId,
                                carrier: trimmedCarrier,
                                trackingNumber: trimmedTrackingNumber
                            )
                        } else {
                            await orderStore.performShipmentAction(
                                .markShipped,
                                orderId: draft.orderId,
                                shipmentId: draft.shipmentId,
                                sellerId: draft.sellerId,
                                carrier: trimmedCarrier,
                                trackingNumber: trimmedTrackingNumber
                            )
                        }
                        pendingShipmentDraft = nil
                    }
                }
            )
        }
        .sheet(item: $selectedProductionPreviewEntry) { preview in
            ProductionPreviewPlayerSheet(preview: preview)
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingProductionPreviewPicker) {
            SystemVideoLibraryPicker(
                isPresented: $isShowingProductionPreviewPicker
            ) { selectedURL in
                guard let target = activeProductionPreviewTarget else { return }
                Task {
                    await uploadProductionPreview(from: selectedURL, for: target)
                }
            } onError: { message in
                orderStore.productionPreviewActionError = message
            }
        }
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

    private func actionTitle(for action: SellerShipmentAction) -> String {
        switch action {
        case .markShipped:
            return "Add Tracking & Mark Shipped"
        case .startProcessing, .markDelivered:
            return action.buttonTitle
        }
    }

    @ViewBuilder
    private func sellerFulfillmentWorkspace(for shipment: Shipment) -> some View {
        GlassCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fulfillment workspace")
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)

                    Text(fulfillmentGuidance(for: shipment))
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    ForEach(shipment.items) { item in
                        sellerProductionPreviewRow(for: item, shipment: shipment)
                    }
                }

                if let nextAction = orderStore.nextAction(for: shipment, order: displayedOrder),
                   nextAction == .markShipped {
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox.and.arrow.trianglehead.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TBTheme.icyBlue)
                        Text("Shipping is the final fulfillment step. Add the purchased label carrier and tracking number when you're ready to send it.")
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func fulfillmentGuidance(for shipment: Shipment) -> String {
        if shipment.status == .delivered {
            return "This shipment is complete. Buyer-facing production updates stay visible in order details."
        }

        if shipment.status == .shipped {
            return "This shipment is on the way. You can mark it delivered once fulfillment is complete."
        }

        if displayedOrder.status == .placed {
            return "Add the private maker video whenever you're ready, then start production to confirm the order and move into the live fulfillment flow."
        }

        return "You're in production now. Add or replace the private maker video here, then finish by saving shipping details and marking the shipment as sent."
    }

    @ViewBuilder
    private func sellerProductionPreviewRow(for item: OrderLineItem, shipment: Shipment) -> some View {
        let existingURL = item.productionPreviewResolvedURL
        let isBusy = productionPreviewBusyItemIDs.contains(item.id)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.productName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(productionPreviewStatusText(existingURL: existingURL, isBusy: isBusy))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(productionPreviewStatusTitle(existingURL: existingURL, isBusy: isBusy))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(productionPreviewStatusColor(existingURL: existingURL, isBusy: isBusy))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.85), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 0.8)
                    )
            }

            HStack(spacing: 10) {
                Button {
                    activeProductionPreviewTarget = SellerProductionPreviewTarget(
                        orderId: displayedOrder.id,
                        shipmentId: shipment.id,
                        sellerId: currentSellerId,
                        orderItemId: item.id,
                        productId: item.productId,
                        productName: item.productName
                    )
                    isShowingProductionPreviewPicker = true
                } label: {
                    fulfillmentActionChip(
                        title: existingURL == nil ? "Add maker video" : "Replace video",
                        systemImage: existingURL == nil ? "video.badge.plus" : "arrow.triangle.2.circlepath"
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .opacity(isBusy ? 0.55 : 1.0)

                if let existingURL {
                    Button {
                        selectedProductionPreviewEntry = ProductionPreviewEntry(
                            productId: item.productId,
                            productName: item.productName,
                            videoURL: existingURL
                        )
                    } label: {
                        fulfillmentActionChip(title: "Preview", systemImage: "play.rectangle.fill")
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        removeProductionPreview(for: item, shipment: shipment)
                    } label: {
                        fulfillmentActionChip(title: "Remove", systemImage: "trash")
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .opacity(isBusy ? 0.55 : 1.0)
                }
            }

        }
        .padding(14)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 0.8)
        )
    }

    private func fulfillmentActionChip(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(TBTheme.deepSky)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.9), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.16), lineWidth: 0.8)
            )
    }

    private func productionPreviewStatusTitle(existingURL: URL?, isBusy: Bool) -> String {
        if isBusy { return "Uploading" }
        if existingURL != nil { return "Ready" }
        return "Missing"
    }

    private func productionPreviewStatusText(existingURL: URL?, isBusy: Bool) -> String {
        if isBusy {
            return "Uploading the latest production update for buyer order details."
        }
        if existingURL != nil {
            return "A private production update is ready for the buyer in order details."
        }
        return "No maker video has been added yet for this order."
    }

    private func productionPreviewStatusColor(existingURL: URL?, isBusy: Bool) -> Color {
        if isBusy { return TBTheme.icyBlue }
        if existingURL != nil { return .green }
        return .orange
    }

    private func removeProductionPreview(for item: OrderLineItem, shipment: Shipment) {
        Task {
            productionPreviewBusyItemIDs.insert(item.id)
            defer { productionPreviewBusyItemIDs.remove(item.id) }

            if isPreviewOrder {
                updatePreviewProductionPreview(
                    shipmentId: shipment.id,
                    orderItemId: item.id,
                    productionPreviewURL: nil
                )
            } else {
                await orderStore.updateOrderProductionPreview(
                    orderId: displayedOrder.id,
                    shipmentId: shipment.id,
                    sellerId: currentSellerId,
                    orderItemId: item.id,
                    productionPreviewURL: nil,
                    removeProductionPreview: true
                )
            }
        }
    }

    private func uploadProductionPreview(from selectedVideoURL: URL, for target: SellerProductionPreviewTarget) async {
        await MainActor.run {
            productionPreviewBusyItemIDs.insert(target.orderItemId)
            orderStore.productionPreviewActionError = nil
        }

        defer {
            Task { @MainActor in
                productionPreviewBusyItemIDs.remove(target.orderItemId)
                activeProductionPreviewTarget = nil
            }
        }

        do {
            guard selectedVideoURL.isFileURL else {
                throw NSError(
                    domain: "OrdersView",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "We couldn't load that maker video."]
                )
            }

            let data = try Data(contentsOf: selectedVideoURL)
            let normalizedExtension = (selectedVideoURL.pathExtension.isEmpty ? "mov" : selectedVideoURL.pathExtension).lowercased()
            if isPreviewOrder {
                let previewFileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(normalizedExtension)
                try data.write(to: previewFileURL, options: .atomic)
                await MainActor.run {
                    updatePreviewProductionPreview(
                        shipmentId: target.shipmentId,
                        orderItemId: target.orderItemId,
                        productionPreviewURL: previewFileURL.absoluteString
                    )
                }
            } else {
                let uploadedURL = try await SellerAPI.uploadMedia(
                    sellerId: target.sellerId,
                    productId: target.productId,
                    mediaKind: "order-maker-video",
                    slot: target.orderItemId,
                    fileExtension: normalizedExtension,
                    contentType: normalizedExtension == "mp4" ? "video/mp4" : "video/quicktime",
                    data: data
                )

                await orderStore.updateOrderProductionPreview(
                    orderId: target.orderId,
                    shipmentId: target.shipmentId,
                    sellerId: target.sellerId,
                    orderItemId: target.orderItemId,
                    productionPreviewURL: uploadedURL
                )
            }
        } catch {
            await MainActor.run {
                orderStore.productionPreviewActionError = error.localizedDescription
            }
        }
    }

    private func handleShipmentAction(_ action: SellerShipmentAction, for shipment: Shipment) {
        switch action {
        case .markShipped:
            carrier = shipment.carrier ?? ""
            trackingNumber = shipment.trackingNumber ?? ""
            pendingShipmentDraft = ShipmentTrackingDraft(
                orderId: order.id,
                shipmentId: shipment.id,
                sellerId: currentSellerId,
                sellerName: shipment.sellerName
            )
        case .startProcessing, .markDelivered:
            if isPreviewOrder {
                applyPreviewShipmentAction(action, shipmentId: shipment.id)
            } else {
                Task {
                    await orderStore.performShipmentAction(
                        action,
                        orderId: displayedOrder.id,
                        shipmentId: shipment.id,
                        sellerId: currentSellerId
                    )
                }
            }
        }
    }

    private func updatePreviewProductionPreview(
        shipmentId: String,
        orderItemId: String,
        productionPreviewURL: String?
    ) {
        guard let shipmentIndex = displayedOrder.shipments.firstIndex(where: { $0.id == shipmentId }),
              let itemIndex = displayedOrder.shipments[shipmentIndex].items.firstIndex(where: { $0.id == orderItemId })
        else { return }

        displayedOrder.shipments[shipmentIndex].items[itemIndex].productionPreviewURL = productionPreviewURL
    }

    private func applyPreviewShipmentAction(
        _ action: SellerShipmentAction,
        shipmentId: String,
        carrier: String? = nil,
        trackingNumber: String? = nil
    ) {
        orderStore.shipmentActionError = nil
        guard let shipmentIndex = displayedOrder.shipments.firstIndex(where: { $0.id == shipmentId }) else { return }
        let timestamp = Date.now

        switch action {
        case .startProcessing:
            displayedOrder.status = .processing
        case .markShipped:
            displayedOrder.shipments[shipmentIndex].status = .shipped
            displayedOrder.shipments[shipmentIndex].shippedAt = timestamp
            displayedOrder.shipments[shipmentIndex].carrier = carrier
            displayedOrder.shipments[shipmentIndex].trackingNumber = trackingNumber
        case .markDelivered:
            displayedOrder.shipments[shipmentIndex].status = .delivered
            displayedOrder.shipments[shipmentIndex].deliveredAt = timestamp
        }

        displayedOrder.status = derivedPreviewOrderStatus(
            from: displayedOrder.shipments,
            current: displayedOrder.status
        )
    }

    private func derivedPreviewOrderStatus(
        from shipments: [Shipment],
        current: OrderStatus
    ) -> OrderStatus {
        guard !shipments.isEmpty else { return current }

        let deliveredCount = shipments.filter { $0.status == .delivered }.count
        let shippedCount = shipments.filter { $0.status == .shipped }.count
        let preparingCount = shipments.filter { $0.status == .preparing }.count

        if deliveredCount == shipments.count {
            return .delivered
        }

        if shippedCount + deliveredCount == shipments.count, shippedCount > 0 {
            return .shipped
        }

        if shippedCount > 0 && preparingCount > 0 {
            return .partiallyShipped
        }

        if preparingCount > 0 {
            return .processing
        }

        return current
    }
}

#if os(iOS)
private struct SystemVideoLibraryPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (URL) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 1
        configuration.filter = nil
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: SystemVideoLibraryPicker

        init(_ parent: SystemVideoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                parent.isPresented = false
                return
            }

            let provider = result.itemProvider
            let movieTypeIdentifiers = [UTType.movie.identifier, UTType.video.identifier]
            guard let movieTypeIdentifier = movieTypeIdentifiers.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
                parent.onError("Please choose a video from your library.")
                parent.isPresented = false
                return
            }

            provider.loadFileRepresentation(forTypeIdentifier: movieTypeIdentifier) { url, error in
                DispatchQueue.main.async {
                    if let error {
                        self.parent.onError(error.localizedDescription)
                        self.parent.isPresented = false
                        return
                    }

                    guard let url else {
                        self.parent.onError("We couldn't load that maker video.")
                        self.parent.isPresented = false
                        return
                    }

                    let fileExtension = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                    let destinationURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(fileExtension)

                    do {
                        if FileManager.default.fileExists(atPath: destinationURL.path) {
                            try FileManager.default.removeItem(at: destinationURL)
                        }
                        try FileManager.default.copyItem(at: url, to: destinationURL)
                        self.parent.onPick(destinationURL)
                    } catch {
                        self.parent.onError("We couldn't prepare that maker video.")
                    }

                    self.parent.isPresented = false
                }
            }
        }
    }
}
#endif

private struct SellerProductionPreviewTarget: Identifiable {
    let orderId: String
    let shipmentId: String
    let sellerId: String
    let orderItemId: String
    let productId: String
    let productName: String

    var id: String {
        "\(orderId)|\(shipmentId)|\(orderItemId)"
    }
}

private struct ShipmentTrackingDraft: Identifiable {
    let orderId: String
    let shipmentId: String
    let sellerId: String
    let sellerName: String

    var id: String {
        "\(orderId)|\(shipmentId)|\(sellerId)"
    }
}

private struct ShipmentTrackingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sellerName: String
    @Binding var carrier: String
    @Binding var trackingNumber: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private var trimmedCarrier: String {
        carrier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTrackingNumber: String {
        trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedCarrier.isEmpty && !trimmedTrackingNumber.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GlassCard(cornerRadius: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Shipping details")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Text("Enter the real carrier and tracking number from the label you bought for \(sellerName). Buyers will see this in their Orders tab.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GlassCard(cornerRadius: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Carrier")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ShipmentTrackingField(title: "USPS, UPS, FedEx, etc.", text: $carrier)
                                .textInputAutocapitalization(.words)

                            Text("Tracking number")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ShipmentTrackingField(title: "Enter the tracking number from the label", text: $trackingNumber)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                        }
                    }

                    Button {
                        onSave()
                        dismiss()
                    } label: {
                        Label("Save Tracking", systemImage: "truck.box.fill")
                            .font(.tbBodyStrong)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true, horizontalPadding: 20, verticalPadding: 12, fontSize: 15))
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.6)
                }
                .padding(16)
            }
            .background(Color.blue.opacity(0.03).ignoresSafeArea())
            .navigationTitle("Add Tracking")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ShipmentTrackingField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.7))
            .cornerRadius(TBTheme.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: TBTheme.radiusMD)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .autocorrectionDisabled()
    }
}

