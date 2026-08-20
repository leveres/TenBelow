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

private enum OrderDateFilter: String, CaseIterable, Identifiable {
    case allTime
    case last30Days
    case last90Days
    case thisYear
    case lastYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allTime:
            return "All dates"
        case .last30Days:
            return "Last 30 days"
        case .last90Days:
            return "Last 90 days"
        case .thisYear:
            return "This year"
        case .lastYear:
            return "Last year"
        }
    }

    var systemImage: String {
        switch self {
        case .allTime:
            return "calendar"
        case .last30Days, .last90Days:
            return "calendar.badge.clock"
        case .thisYear, .lastYear:
            return "calendar.badge.checkmark"
        }
    }

    func dateInterval(calendar: Calendar = .current, now: Date = .now) -> DateInterval? {
        switch self {
        case .allTime:
            return nil
        case .last30Days:
            return daysBack(30, calendar: calendar, now: now)
        case .last90Days:
            return daysBack(90, calendar: calendar, now: now)
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now)
        case .lastYear:
            guard let currentYear = calendar.dateInterval(of: .year, for: now),
                  let previousYearStart = calendar.date(byAdding: .year, value: -1, to: currentYear.start) else {
                return nil
            }
            return DateInterval(start: previousYearStart, end: currentYear.start)
        }
    }

    func includes(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> Bool {
        guard let interval = dateInterval(calendar: calendar, now: now) else { return true }
        return date >= interval.start && date < interval.end
    }

    private func daysBack(_ days: Int, calendar: Calendar, now: Date) -> DateInterval? {
        let todayStart = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: todayStart),
              let end = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }
}

struct OrdersView: View {
    private enum HeroMetrics {
        static let titleImageHeight: CGFloat = 56
        static let titleImageScale: CGFloat = 1.45
        static let snowfallCornerRadius: CGFloat = 12
        static let snowfallHorizontalPadding: CGFloat = 8
        static let snowfallVerticalPadding: CGFloat = 2
        static let snowfallFlakeCount: Int = 30
        static let headerSpacing: CGFloat = 0
        static let sectionSpacing: CGFloat = 4
        static let dateFilterChipWidth: CGFloat = 132
        static let dateFilterChipHeight: CGFloat = 44
        static let dateFilterClearButtonWidth: CGFloat = 44
    }

    @EnvironmentObject private var orderStore: OrderStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @AppStorage("userRole") private var userRole = "buyer"
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @AppStorage("sellerSellerId") private var sellerId = ""
    @State private var selectedFilter: OrderListFilter = .all
    @State private var selectedDateFilter: OrderDateFilter = .allTime
    @State private var lastOrdersRefresh = Date.distantPast

#if os(iOS)
    private enum Haptics {
        static let selection = UIImpactFeedbackGenerator(style: .light)
    }
#endif

    /// Mode is driven by role picked at app start — no segmented control.
    private var mode: OrdersMode {
        userRole == "seller" ? .seller : .buyer
    }

    private var productsById: [String: Product] {
        Dictionary(uniqueKeysWithValues: localProducts.products.map { ($0.id, $0) })
    }

    private var hasRegisteredSeller: Bool {
        !sellerId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var effectiveSellerId: String? {
        guard mode == .seller, hasRegisteredSeller else { return nil }
        return sellerId
    }

    var body: some View {
        let statusOrders = baseOrders
        let visibleOrders = filteredOrders

        Group {
            if orderStore.isRefreshing, visibleOrders.isEmpty {
                loadingState
            } else if visibleOrders.isEmpty {
                emptyState(statusBarOrders: statusOrders)
            } else {
                ordersList(statusBarOrders: statusOrders, visibleOrders: visibleOrders)
            }
        }
        .background(TBFrostBackground())
        .navigationTitle("")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: "\(mode.rawValue)|\(buyerEmail)|\(sellerId)") {
            await refreshOrders()
        }
        .onChange(of: selectedFilter) { _, newFilter in
            guard newFilter != .completed, selectedDateFilter != .allTime else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedDateFilter = .allTime
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

    private func emptyState(statusBarOrders: [Order]) -> some View {
        VStack(spacing: 0) {
            ordersHeaderBlock(statusBarOrders: statusBarOrders)

            ScrollView {
                VStack(spacing: 10) {
                    Text(emptyStateTitle)
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

    private func ordersList(statusBarOrders: [Order], visibleOrders: [Order]) -> some View {
        VStack(spacing: 0) {
            ordersHeaderBlock(statusBarOrders: statusBarOrders)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(visibleOrders) { order in
                        NavigationLink {
                            OrderDetailView(
                                orderId: order.id,
                                mode: mode,
                                currentSellerId: effectiveSellerId
                            )
                        } label: {
                            OrderRowCard(
                                order: order,
                                productsById: productsById,
                                hasPendingCancellation: hasPendingCancellation(order)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("orders.row.\(order.id)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(
                    .bottom,
                    TopLevelHeaderMetrics.homeFloatingTabBarClearance + 52
                )
            }
            .transaction { transaction in
                transaction.disablesAnimations = true
            }
            .animation(nil, value: visibleOrders.count)
            .refreshable {
                await refreshOrders(force: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ordersHeaderBlock(statusBarOrders: [Order]) -> some View {
        GlassCard(cornerRadius: 16, contentPadding: 9) {
            VStack(alignment: .center, spacing: HeroMetrics.sectionSpacing) {
                VStack(alignment: .center, spacing: HeroMetrics.headerSpacing) {
                    SnowfallTitleContainer(
                        cornerRadius: HeroMetrics.snowfallCornerRadius,
                        horizontalPadding: HeroMetrics.snowfallHorizontalPadding,
                        verticalPadding: HeroMetrics.snowfallVerticalPadding,
                        flakeCount: HeroMetrics.snowfallFlakeCount,
                        effectHorizontalInset: 10,
                        effectVerticalInset: 8
                    ) {
                        Image("OrdersTitle")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: HeroMetrics.titleImageHeight)
                            .scaleEffect(HeroMetrics.titleImageScale)
                            .accessibilityLabel("Orders")
                            .accessibilityAddTraits(.isHeader)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    Text(mode == .buyer
                         ? "Your purchases and delivery updates."
                         : "Manage fulfillment and customer orders.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                OrdersStatusBar(
                    orders: statusBarOrders,
                    mode: mode,
                    sellerId: effectiveSellerId,
                    selectedFilter: $selectedFilter
                )
                .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Spacer(minLength: 0)
                    completedDateFilterMenu
                }
            }
            .animation(nil, value: selectedFilter)
            .animation(nil, value: selectedDateFilter)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var isDateFilterApplied: Bool {
        selectedDateFilter != .allTime
    }

    private var completedDateFilterMenu: some View {
        HStack(spacing: 7) {
            Menu {
                Section("Show completed orders from") {
                    ForEach(OrderDateFilter.allCases) { filter in
                        Button {
                            applyDateFilterSelection(filter)
                        } label: {
                            if selectedDateFilter == filter {
                                Label(filter.title, systemImage: "checkmark")
                            } else {
                                Text(filter.title)
                            }
                        }
                    }
                }
            } label: {
                dateFilterPill
            }
            .menuStyle(.button)
            .accessibilityLabel("Filter completed orders by date")
            .accessibilityValue(selectedDateFilter.title)

            Button {
                triggerSelectionHaptic()
                clearDateFilter()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.65), in: Circle())
                    .frame(
                        width: HeroMetrics.dateFilterClearButtonWidth,
                        height: HeroMetrics.dateFilterClearButtonWidth
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainChipButtonStyle())
            .opacity(selectedDateFilter == .allTime ? 0 : 1)
            .allowsHitTesting(selectedDateFilter != .allTime)
            .accessibilityHidden(selectedDateFilter == .allTime)
            .accessibilityLabel("Clear completed orders date filter")
            .frame(
                width: HeroMetrics.dateFilterClearButtonWidth,
                height: HeroMetrics.dateFilterClearButtonWidth
            )
        }
        .frame(height: HeroMetrics.dateFilterChipHeight, alignment: .center)
        .transaction { $0.disablesAnimations = true }
        .animation(nil, value: selectedDateFilter)
    }

    private var dateFilterPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13, weight: .semibold))
            Text(selectedDateFilter.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .foregroundStyle(isDateFilterApplied ? TBTheme.deepSky : Color.primary.opacity(0.64))
        .frame(width: HeroMetrics.dateFilterChipWidth, height: HeroMetrics.dateFilterChipHeight)
        .background(
            isDateFilterApplied
                ? TBTheme.skyBlue.opacity(0.10)
                : Color.white.opacity(0.68),
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    isDateFilterApplied
                        ? TBTheme.skyBlue.opacity(0.18)
                        : TBTheme.skyBlue.opacity(0.10),
                    lineWidth: 0.8
                )
        }
        .contentShape(Capsule(style: .continuous))
        .animation(nil, value: isDateFilterApplied)
    }

    private var baseOrders: [Order] {
        switch mode {
        case .buyer: return orderStore.orders
        case .seller:
            guard let effectiveSellerId else { return [] }
            return orderStore.orders.filter { $0.shipments.contains { $0.sellerId == effectiveSellerId } }
        }
    }

    private var filteredOrders: [Order] {
        guard selectedDateFilter != .allTime else {
            return sortOrders(filtered(baseOrders, for: selectedFilter))
        }

        let calendar = Calendar.current
        let now = Date.now
        let activeInterval = selectedDateFilter.dateInterval(calendar: calendar, now: now)

        let dateFiltered = filtered(baseOrders, for: .completed).filter { order in
            guard let date = completedDate(for: order) else { return false }
            guard let activeInterval else { return true }
            return activeInterval.contains(date)
        }
        return sortOrders(dateFiltered)
    }

    private func applyDateFilterSelection(_ filter: OrderDateFilter) {
#if os(iOS)
        triggerSelectionHaptic()
#endif
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedDateFilter = filter
            selectedFilter = .completed
        }
    }

    private func clearDateFilter() {
#if os(iOS)
        triggerSelectionHaptic()
#endif
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedDateFilter = .allTime
            if selectedFilter == .completed {
                selectedFilter = .all
            }
        }
    }

#if os(iOS)
    private func triggerSelectionHaptic() {
        Haptics.selection.prepare()
        Haptics.selection.impactOccurred(intensity: 0.75)
    }
#endif

    private var emptyStateMessage: String {
        if let refreshError = orderStore.refreshError {
            return refreshError
        }

        if mode == .buyer {
            return "Your orders will appear here with live status updates."
        }

        if !hasRegisteredSeller {
            return "Create or sign in to your seller account from the app start screen to load orders for your store."
        }

        return "Orders from your store will appear here."
    }

    private var emptyStateTitle: String {
        guard !baseOrders.isEmpty else {
            return mode == .buyer ? "No orders yet" : "No orders to fulfill"
        }

        switch selectedFilter {
        case .all:
            return mode == .buyer ? "No orders yet" : "No orders to fulfill"
        case .active:
            return "No active orders"
        case .completed:
            return selectedDateFilter == .allTime ? "No completed orders" : "No completed orders in this range"
        }
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

    private func sortOrders(_ orders: [Order]) -> [Order] {
        orders.sorted { lhs, rhs in
            let lhsPriority = statusPriority(lhs.status)
            let rhsPriority = statusPriority(rhs.status)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func statusPriority(_ status: OrderStatus) -> Int {
        switch status {
        case .processing:
            return 0
        case .placed:
            return 1
        case .partiallyShipped:
            return 2
        case .shipped:
            return 3
        case .delivered:
            return 4
        default:
            return 5
        }
    }

    private func isCompletedForCurrentMode(_ order: Order) -> Bool {
        switch mode {
        case .buyer:
            return order.status == .shipped || order.status == .delivered || order.status == .cancelled
        case .seller:
            guard let effectiveSellerId else { return false }
            let myShipments = order.shipments.filter { $0.sellerId == effectiveSellerId }
            guard !myShipments.isEmpty else { return false }
            return myShipments.allSatisfy { $0.status == .shipped || $0.status == .delivered || $0.status == .cancelled }
        }
    }

    /// True when this order has a pending cancel request relevant to the current mode.
    private func hasPendingCancellation(_ order: Order) -> Bool {
        order.supportRequests.contains { request in
            guard request.type == .cancel, request.status == .pending else { return false }
            if mode == .seller, let effectiveSellerId {
                return request.sellerId == effectiveSellerId
            }
            return true
        }
    }

    private func completedDate(for order: Order) -> Date? {
        switch mode {
        case .buyer:
            return order.deliveredAt
                ?? order.shipments.compactMap(\.deliveredAt).max()
                ?? order.shipments.compactMap(\.shippedAt).max()
                ?? order.createdAt
        case .seller:
            guard let effectiveSellerId else { return order.createdAt }
            let myShipments = order.shipments.filter { $0.sellerId == effectiveSellerId }
            return myShipments.compactMap(\.deliveredAt).max()
                ?? myShipments.compactMap(\.shippedAt).max()
                ?? order.createdAt
        }
    }

    private func refreshOrders(force: Bool = false) async {
        guard !orderStore.isRefreshing else { return }

        let now = Date()
        guard force || now.timeIntervalSince(lastOrdersRefresh) > 45 else { return }
        lastOrdersRefresh = now

        switch mode {
        case .buyer:
            await orderStore.refreshBuyerOrders(email: buyerEmail)
        case .seller:
            guard hasRegisteredSeller else { return }
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

private enum BuyerOrderSupportSheet: Identifiable {
    case thread(sellerId: String, sellerName: String)
    case request(Shipment, OrderSupportRequestType)

    var id: String {
        switch self {
        case .thread(let sellerId, _): return "thread-\(sellerId)"
        case .request(let shipment, let type): return "request-\(shipment.id)-\(type.rawValue)"
        }
    }
}

struct BuyerOrderDetailView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var exchangeStore: ExchangeStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @EnvironmentObject private var orderStore: OrderStore
    let order: Order
    private var activeOrder: Order {
        orderStore.order(withId: order.id) ?? order
    }
    @State private var selectedProductionPreview: ProductionPreviewEntry?
    @State private var exchangeSheet: BuyerExchangeSheet?
    @State private var showExchangePolicyBrowser = false
    @State private var supportSheet: BuyerOrderSupportSheet?

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
                                Text(activeOrder.id)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                            OrderStatusPill(status: activeOrder.status)
                        }

                        Text(activeOrder.createdAt.formatted(date: .long, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("This order ships in \(activeOrder.shipments.count) shipment\(activeOrder.shipments.count == 1 ? "" : "s") from different sellers.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let city = activeOrder.shipToCity, let state = activeOrder.shipToState {
                            Label("Delivering to \(city), \(state)", systemImage: "location.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let email = activeOrder.buyerEmail {
                            Label("Receipt: \(email)", systemImage: "envelope.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                OrderTimelineView(order: activeOrder)
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

                    ForEach(activeOrder.shipments) { shipment in
                        ShipmentCard(shipment: shipment, mode: .buyer)
                            .padding(.horizontal, 16)
                    }
                }

                buyerExchangeSection
                    .padding(.horizontal, 16)

                buyerSupportSection
                    .padding(.horizontal, 16)

                GlassCard(cornerRadius: 20) {
                    HStack {
                        Text("Order Total")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatMoney(activeOrder.totalCents, activeOrder.currency))
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(TBFrostBackground())
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
                    order: activeOrder,
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
        .sheet(item: $supportSheet) { sheet in
            switch sheet {
            case .thread(let sellerId, let sellerName):
                OrderSupportThreadView(
                    orderId: order.id,
                    sellerId: sellerId,
                    sellerName: sellerName,
                    viewerRole: .buyer
                )
                .environmentObject(orderStore)
            case .request(let shipment, let type):
                OrderSupportRequestSheet(order: activeOrder, shipment: shipment, requestType: type)
                    .environmentObject(orderStore)
            }
        }
        .task(id: order.id) {
            _ = try? await exchangeStore.refreshRequests(for: order.id)
        }
    }

    private var buyerSupportSection: some View {
        GlassCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Help & support")
                    .font(.headline)
                    .fontWeight(.semibold)

                PolicyNoticeCard(
                    bodyText: MarketplacePolicyCopy.buyerOrderSupportIntro,
                    tone: .support
                )

                OrderSupportRequestsSection(order: activeOrder, sellerId: nil, isSellerView: false, embeddedInCard: true)
                    .environmentObject(orderStore)

                ForEach(activeOrder.shipments) { shipment in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(shipment.sellerName)
                            .font(.tbBodyStrong)
                            .foregroundStyle(TBTheme.deepSky)

                        Button {
                            supportSheet = .thread(sellerId: shipment.sellerId, sellerName: shipment.sellerName)
                        } label: {
                            Label("Message \(shipment.sellerName)", systemImage: "bubble.left.and.bubble.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(TBTheme.icyBlue)

                        if shipment.status == .preparing {
                            let hasPendingCancel = activeOrder.supportRequests.contains {
                                $0.type == .cancel && $0.status == .pending && $0.shipmentId == shipment.id
                            }
                            if hasPendingCancel {
                                supportPendingBanner("Cancellation request pending", tint: .orange)
                            } else if buyerCanRequestCancel(for: shipment, hasPendingCancel: hasPendingCancel) {
                                Button {
                                    supportSheet = .request(shipment, .cancel)
                                } label: {
                                    Label("Request cancellation", systemImage: "xmark.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if shipment.status == .shipped || shipment.status == .delivered {
                            let hasPendingRefund = activeOrder.supportRequests.contains {
                                $0.type == .refund && $0.status == .pending && $0.shipmentId == shipment.id
                            }
                            if hasPendingRefund {
                                supportPendingBanner("Refund request pending", tint: .orange)
                            } else if buyerCanRequestRefund(for: shipment, hasPendingRefund: hasPendingRefund) {
                                Button {
                                    supportSheet = .request(shipment, .refund)
                                } label: {
                                    Label("Request refund", systemImage: "dollarsign.arrow.circlepath")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func buyerCanRequestCancel(for shipment: Shipment, hasPendingCancel: Bool) -> Bool {
        guard shipment.status == .preparing, !hasPendingCancel else { return false }
        return shipment.supportEligibility?.canRequestCancel ?? true
    }

    private func buyerCanRequestRefund(for shipment: Shipment, hasPendingRefund: Bool) -> Bool {
        guard shipment.status == .shipped || shipment.status == .delivered, !hasPendingRefund else { return false }
        return shipment.supportEligibility?.canRequestRefund ?? false
    }

    @ViewBuilder
    private func supportPendingBanner(_ title: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }

    private var buyerExchangeSection: some View {
        GlassCard(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Exchanges")
                    .font(.headline)
                    .fontWeight(.semibold)

                PolicyNoticeCard(
                    bodyText: MarketplacePolicyCopy.buyerExchangeIntro,
                    tone: .exchange
                )

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
                    Text(MarketplacePolicyCopy.readExchangePolicyButton)
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
        activeOrder.shipments.flatMap { shipment in
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
            return MarketplacePolicyCopy.buyerExchangeAfterDelivery
        }
        if exchangeItemContexts.allSatisfy({ ($0.item.exchangeCount ?? 0) >= catalog.config.maxExchangeCountPerOrderItem }) {
            return MarketplacePolicyCopy.buyerExchangeUsed
        }
        return MarketplacePolicyCopy.buyerExchangeUnavailable
    }

    private var orderLineItems: [OrderLineItem] {
        activeOrder.shipments.flatMap(\.items)
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
                    selectedColor: item.selectedColor,
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

                                if let color = preview.selectedColor {
                                    HStack(spacing: 5) {
                                        ProductColorSwatch(hex: color.hex, size: 12)
                                        Text("Made in \(color.name)")
                                    }
                                    .font(.tbCaption.weight(.semibold))
                                    .foregroundStyle(TBTheme.accent)
                                }

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
    var selectedColor: ProductColorOption? = nil
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
    @State private var showBuyerSupportThread = false
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

                                if orderStore.canUpdateTracking(for: shipment) {
                                    Button {
                                        handleShipmentAction(.updateTracking, for: shipment)
                                    } label: {
                                        Label("Update tracking", systemImage: "barcode.viewfinder")
                                            .font(.tbBodyStrong)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(TBTheme.icyBlue)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                OrderSupportRequestsSection(
                    order: displayedOrder,
                    sellerId: currentSellerId,
                    isSellerView: true
                )
                .environmentObject(orderStore)
                .padding(.horizontal, 16)

                GlassCard(cornerRadius: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Buyer support")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("Use a private thread for shipping updates, missing package questions, or refund/cancel follow-up.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            showBuyerSupportThread = true
                        } label: {
                            Label("Message buyer", systemImage: "bubble.left.and.bubble.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true, horizontalPadding: 20, verticalPadding: 12, fontSize: 15))
                    }
                }
                .padding(.horizontal, 16)

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
        .background(TBFrostBackground())
        .navigationTitle("Fulfill order")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: order) { _, newOrder in
            if !isPreviewOrder {
                displayedOrder = newOrder
            }
        }
        .onChange(of: orderStore.orders) { _, _ in
            if let latest = orderStore.order(withId: order.id), !isPreviewOrder {
                displayedOrder = latest
            }
        }
        .sheet(isPresented: $showBuyerSupportThread) {
            OrderSupportThreadView(
                orderId: displayedOrder.id,
                sellerId: currentSellerId,
                sellerName: myShipments.first?.sellerName ?? currentSellerId,
                viewerRole: .seller
            )
            .environmentObject(orderStore)
        }
        .sheet(item: $pendingShipmentDraft) { draft in
            ShipmentTrackingSheet(
                sellerName: draft.sellerName,
                trackingAction: draft.trackingAction,
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
                        let action = draft.trackingAction
                        if isPreviewOrder {
                            applyPreviewShipmentAction(
                                action,
                                shipmentId: draft.shipmentId,
                                carrier: trimmedCarrier,
                                trackingNumber: trimmedTrackingNumber
                            )
                        } else {
                            await orderStore.performShipmentAction(
                                action,
                                orderId: draft.orderId,
                                shipmentId: draft.shipmentId,
                                sellerId: draft.sellerId,
                                carrier: trimmedCarrier,
                                trackingNumber: trimmedTrackingNumber
                            )
                            if let latest = orderStore.order(withId: draft.orderId) {
                                displayedOrder = latest
                            }
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
        case .updateTracking:
            return "barcode.viewfinder"
        }
    }

    private func actionTitle(for action: SellerShipmentAction) -> String {
        switch action {
        case .markShipped:
            return "Add Tracking & Mark Shipped"
        case .startProcessing, .markDelivered, .updateTracking:
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

                    if let color = item.selectedColor {
                        HStack(spacing: 5) {
                            ProductColorSwatch(hex: color.hex, size: 13)
                            Text("Make in \(color.name)")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TBTheme.accent)
                    }

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
                            selectedColor: item.selectedColor,
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

            await Task.yield()
            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: selectedVideoURL)
            }.value
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
        case .markShipped, .updateTracking:
            carrier = shipment.carrier ?? ""
            trackingNumber = shipment.trackingNumber ?? ""
            pendingShipmentDraft = ShipmentTrackingDraft(
                orderId: order.id,
                shipmentId: shipment.id,
                sellerId: currentSellerId,
                sellerName: shipment.sellerName,
                trackingAction: action
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
        case .updateTracking:
            displayedOrder.shipments[shipmentIndex].carrier = carrier
            displayedOrder.shipments[shipmentIndex].trackingNumber = trackingNumber
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
                if let error {
                    Task { @MainActor in
                        self.parent.onError(error.localizedDescription)
                        self.parent.isPresented = false
                    }
                    return
                }

                guard let url else {
                    Task { @MainActor in
                        self.parent.onError("We couldn't load that maker video.")
                        self.parent.isPresented = false
                    }
                    return
                }

                Task.detached(priority: .userInitiated) {
                    let fileExtension = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                    let destinationURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(fileExtension)

                    do {
                        if FileManager.default.fileExists(atPath: destinationURL.path) {
                            try FileManager.default.removeItem(at: destinationURL)
                        }
                        try FileManager.default.copyItem(at: url, to: destinationURL)
                        await MainActor.run {
                            self.parent.onPick(destinationURL)
                            self.parent.isPresented = false
                        }
                    } catch {
                        await MainActor.run {
                            self.parent.onError("We couldn't prepare that maker video.")
                            self.parent.isPresented = false
                        }
                    }
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
    let trackingAction: SellerShipmentAction

    var id: String {
        "\(orderId)|\(shipmentId)|\(sellerId)|\(trackingAction.rawValue)"
    }
}

private struct ShipmentTrackingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sellerName: String
    let trackingAction: SellerShipmentAction
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
            .background(TBFrostBackground())
            .navigationTitle(trackingAction == .updateTracking ? "Update Tracking" : "Add Tracking")
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

private struct PlainChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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

