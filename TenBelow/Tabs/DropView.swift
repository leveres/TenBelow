//
//  DropView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import Combine

private enum WeeklyDropPreviewMode: String, CaseIterable, Identifiable {
    case liveData
    case beforeFriday
    case thursdayPreview
    case fridaySubmitting
    case weekendLive
    case closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveData:
            return "Live Data"
        case .beforeFriday:
            return "Before Friday"
        case .thursdayPreview:
            return "Thursday Submissions Open"
        case .fridaySubmitting:
            return "Friday Live"
        case .weekendLive:
            return "Weekend Live"
        case .closed:
            return "Drop Closed"
        }
    }

    var symbolName: String {
        switch self {
        case .liveData:
            return "dot.radiowaves.left.and.right"
        case .beforeFriday:
            return "calendar.badge.clock"
        case .thursdayPreview:
            return "shippingbox.fill"
        case .fridaySubmitting:
            return "sparkles"
        case .weekendLive:
            return "shippingbox.fill"
        case .closed:
            return "moon.stars.fill"
        }
    }
}

struct DropView: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore
    @AppStorage("userRole") private var userRole = ""
    @AppStorage("sellerSellerId") private var sellerId = ""
    @AppStorage("sellerPreviewMode") private var sellerPreviewMode = false
    @AppStorage("weeklyDropPreviewMode") private var weeklyDropPreviewModeRaw = WeeklyDropPreviewMode.liveData.rawValue
    @State private var showCart = false
    @State private var dropResponse: CurrentDropResponse?
    @State private var sellerSubmissions: SellerSubmissionsResponse?
    @State private var sellerDropHistory: SellerDropHistoryResponse?
    @State private var selectedHistoryWeekId: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showDropSubmit = false
    @State private var selectedDropProduct: Product?
    @State private var buyerProductsPage = 0
    @State private var countdownNow = Date()
    @State private var previewAnchorNow = Date()
    @State private var lastDropLoad = Date.distantPast
    @State private var lastSubscriptionRefresh = Date.distantPast
    @State private var isDropLoadInFlight = false
    @State private var isDropVisible = false
    /// Off by default; turn on from Settings → Developer (DEBUG) to preview the buyer Drop lineup without live data.
    @AppStorage("buyerDropPreviewMode") private var buyerDropPreviewMode = false
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let previewDateFormatter = ISO8601DateFormatter()

    private var weeklyDropPreviewMode: WeeklyDropPreviewMode {
        WeeklyDropPreviewMode(rawValue: weeklyDropPreviewModeRaw) ?? .liveData
    }

    private var isUsingWeeklyDropPreview: Bool {
        weeklyDropPreviewMode != .liveData
    }

    private var effectiveDropResponse: CurrentDropResponse? {
        previewCurrentDropResponse ?? dropResponse
    }

    private var effectiveSellerSubmissions: SellerSubmissionsResponse? {
        previewSellerSubmissions ?? sellerSubmissions
    }

    private var isActive: Bool { effectiveDropResponse?.active == true }
    private var dropProducts: [DropProduct] { effectiveDropResponse?.products ?? [] }
    private var weeklyDropProducts: [DropProduct] {
        dropProducts.filter { $0.priceCents >= DropConstants.minPriceCents }
    }
    private var buyerPreviewDropProducts: [DropProduct] {
        let source = resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: MockData.products
        )
        return source.enumerated().map { entry in
            let index = entry.offset
            let product = entry.element
            return DropProduct(
                id: "buyer-preview-drop-\(index)-\(product.id)",
                sellerId: product.sellerId,
                name: product.name,
                priceCents: max(product.priceCents, 1200),
                previousPriceCents: product.previousPriceCents,
                category: product.category.rawValue,
                imageURLs: product.imageNames,
                demoVideoURL: product.demoVideoURL?.absoluteString,
                productionPreviewURL: product.productionPreviewURL?.absoluteString,
                headline: "Preview release",
                story: "A preview of the premium Friday lineup.",
                bestUseCase: "Buyer-facing preview data",
                material: product.material,
                durabilityNote: "Preview sample",
                careWarnings: [],
                shipsInMinDays: 2,
                shipsInMaxDays: 4,
                approvalStatus: .approved,
                reviewNotes: nil,
                reviewedAt: nil,
                submittedAt: "preview",
                slotNumber: index + 1
            )
        }
    }
    private var shouldShowBuyerDropPreview: Bool {
        if isUsingWeeklyDropPreview {
            return false
        }
        return !isSeller && !isActive && !buyerPreviewDropProducts.isEmpty && buyerDropPreviewMode
    }
    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var sellerProfilesByID: [String: SellerProfile] {
        resolvedSellerProfilesByID(
            storefrontProducts: storefrontProducts,
            remoteProfiles: catalog.sellerProfiles
        )
    }
    private var isSeller: Bool { userRole == "seller" && !sellerId.isEmpty }
    private var sellerSubmissionProducts: [DropProduct] { effectiveSellerSubmissions?.products ?? [] }
    private var sellerHistoryWeeks: [SellerDropHistoryWeek] { sellerDropHistory?.weeks ?? [] }
    private var sellerDisplayHistoryWeeks: [SellerDropHistoryWeek] {
        var weeks = sellerHistoryWeeks
        guard !submissionWindowOpen, !sellerSubmissionProducts.isEmpty else {
            return weeks
        }

        let currentWeekId = effectiveSellerSubmissions?.weekId ?? effectiveDropResponse?.weekId ?? "current-weekly-drop"
        if weeks.contains(where: { $0.weekId == currentWeekId }) {
            return weeks
        }

        let fallbackDate = previewDateFormatter.string(from: countdownNow)
        let currentWeek = SellerDropHistoryWeek(
            weekId: currentWeekId,
            startsAt: effectiveDropResponse?.startsAt ?? sellerSubmissionProducts.first?.submittedAt ?? fallbackDate,
            endsAt: effectiveDropResponse?.endsAt ?? fallbackDate,
            postedCount: sellerSubmissionProducts.count,
            soldCount: 0,
            products: sellerSubmissionProducts
        )
        weeks.insert(currentWeek, at: 0)
        return weeks
    }
    private var selectedHistoryWeek: SellerDropHistoryWeek? {
        if let selectedHistoryWeekId,
           let match = sellerDisplayHistoryWeeks.first(where: { $0.weekId == selectedHistoryWeekId }) {
            return match
        }
        return sellerDisplayHistoryWeeks.first
    }
    private var slotsUsed: Int { effectiveSellerSubmissions?.slotsUsed ?? 0 }
    private var slotsMax: Int { effectiveSellerSubmissions?.slotsMax ?? DropConstants.maxSlotsPerSeller }
    private var slotsRemaining: Int { max(slotsMax - slotsUsed, 0) }
    private var sellerHasWeeklyDropAccess: Bool {
        isUsingWeeklyDropPreview
            || sellerPreviewMode
            || sellerSubscription.hasActiveSubscription
    }
    private var submissionWindowOpen: Bool {
        WeekendDropManager.isSubmissionWindowOpen(now: countdownNow, currentDrop: effectiveDropResponse)
    }
    private var buyerLiveBoardState: WeekendDropState {
        WeekendDropManager.state(
            now: countdownNow,
            currentDrop: effectiveDropResponse,
            products: weeklyDropProducts,
            audience: .buyer
        )
    }
    private var buyerThursdayPreviewState: WeekendDropState {
        WeekendDropManager.state(
            now: countdownNow,
            currentDrop: effectiveDropResponse,
            products: weeklyDropProducts,
            audience: .buyer
        )
    }
    private var buyerPreviewBoardState: WeekendDropState {
        let base = WeekendDropManager.state(
            now: countdownNow,
            currentDrop: effectiveDropResponse,
            products: weeklyDropProducts,
            audience: .buyer
        )
        let previewCount = buyerPreviewDropProducts.count
        if previewCount > 0, base.itemCount == 0 {
            return WeekendDropState(
                phase: base.phase,
                schedule: base.schedule,
                headline: base.headline,
                promoPhrases: base.promoPhrases,
                itemCount: previewCount,
                accentSymbolName: base.accentSymbolName,
                usesPreviewData: true
            )
        }
        return base
    }

    /// Resets buyer pagination when the active buyer list or mode changes.
    private var buyerProductListFingerprint: String {
        if isUsingWeeklyDropPreview {
            return "\(weeklyDropPreviewMode.rawValue)|\(dropProducts.map(\.id).joined(separator: ","))"
        }
        if shouldShowBuyerDropPreview {
            return "preview|\(buyerPreviewDropProducts.map(\.id).joined(separator: ","))"
        }
        if buyerThursdayPreviewState.isThursdayPreview && !weeklyDropProducts.isEmpty {
            return "thursday|\(weeklyDropProducts.map(\.id).joined(separator: ","))"
        }
        if buyerLiveBoardState.isLive && !weeklyDropProducts.isEmpty {
            return "live|\(weeklyDropProducts.map(\.id).joined(separator: ","))"
        }
        return "inactive"
    }

    private enum DropLayoutMetrics {
        static let buyerHeaderStackSpacing: CGFloat = 0
        /// Tuned down slightly so the buyer Drop hero sits higher on screen (less empty space under the nav chrome).
        static let buyerTitleHeight: CGFloat = 158
        static let buyerTitleBottomTuck: CGFloat = -34
        static let buyerTitleCardOverlap: CGFloat = -16
        static let buyerContentTopInset: CGFloat = -18
        static let buyerInactiveHeroTopSpacing: CGFloat = 0
        static let buyerInactiveHeroBottomSpacing: CGFloat = 84
        /// Seller hub: tighter vertical rhythm than buyer (smaller title art + less gap to badge/hero).
        static let sellerHeaderSpacing: CGFloat = 2
        static let sellerTitleHeight: CGFloat = 148
        static let sellerTitleBottomTuck: CGFloat = -32
        static let sellerContentTopInset: CGFloat = -18
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSeller {
                    sellerDropHubContent
                } else if isUsingWeeklyDropPreview, weeklyDropPreviewMode == .beforeFriday || weeklyDropPreviewMode == .thursdayPreview {
                    buyerInactiveDropContent
                } else if isUsingWeeklyDropPreview, weeklyDropPreviewMode == .fridaySubmitting || weeklyDropPreviewMode == .weekendLive {
                    buyerActiveDropContent
                } else if isUsingWeeklyDropPreview, weeklyDropPreviewMode == .closed {
                    buyerInactiveDropContent
                } else if buyerThursdayPreviewState.isThursdayPreview && !weeklyDropProducts.isEmpty {
                    buyerThursdayPreviewContent
                } else if shouldShowBuyerDropPreview {
                    buyerPreviewDropContent
                } else if buyerLiveBoardState.isLive && !weeklyDropProducts.isEmpty {
                    buyerActiveDropContent
                } else {
                    buyerInactiveDropContent
                }
            }
            .background(TBTheme.cloudWhite)
            .navigationTitle("")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    weeklyDropPreviewMenu
                }
                if !isSeller {
                    ToolbarItem(placement: .topBarTrailing) {
                        CartButton(itemCount: cart.items.reduce(0) { $0 + $1.quantity }) {
                            showCart = true
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    weeklyDropPreviewMenu
                }
                if !isSeller {
                    ToolbarItem(placement: .automatic) {
                        CartButton(itemCount: cart.items.reduce(0) { $0 + $1.quantity }) {
                            showCart = true
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
            #endif
            .sheet(isPresented: $showCart) {
                CartView()
                    .environmentObject(cart)
                    .environmentObject(catalog)
            }
            .navigationDestination(isPresented: $showDropSubmit) {
                DropSubmitView(
                    currentDrop: effectiveDropResponse,
                    referenceDate: countdownNow,
                    initialSubmissions: effectiveSellerSubmissions,
                    usesPreviewData: isUsingWeeklyDropPreview
                )
            }
            .navigationDestination(item: $selectedDropProduct) { product in
                ProductDetailView(product: product)
            }
            .task {
                await loadDropIfNeeded()
                await refreshSubscriptionIfNeeded()
            }
            .onReceive(countdownTimer) { now in
                guard isDropVisible else { return }
                countdownNow = now
            }
            .onAppear {
                isDropVisible = true
                previewAnchorNow = countdownNow
            }
            .onDisappear {
                isDropVisible = false
            }
            .onChange(of: buyerProductListFingerprint) { _, _ in
                buyerProductsPage = 0
            }
            .onChange(of: weeklyDropPreviewModeRaw) { _, _ in
                previewAnchorNow = countdownNow
                buyerProductsPage = 0
            }
        }
    }

    // MARK: - Buyer Active Drop

    @ViewBuilder
    private var buyerActiveDropContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DropLayoutMetrics.buyerHeaderStackSpacing) {
                SnowfallTitleContainer(cornerRadius: 28, horizontalPadding: 18, verticalPadding: 5, flakeCount: 82) {
                    Image("WeeklyDropTitle")
                        .resizable()
                        .scaledToFit()
                        .frame(height: DropLayoutMetrics.buyerTitleHeight)
                        .padding(.bottom, DropLayoutMetrics.buyerTitleBottomTuck)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DropLayoutMetrics.buyerTitleCardOverlap)

                weeklyDropPreviewBadge
                WeeklyDropBoardCard(state: buyerLiveBoardState, now: countdownNow)

                Text("Limited-time premium releases from makers across TenBelow. These picks stay live through Sunday night.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
            .padding(.top, DropLayoutMetrics.buyerContentTopInset)

            buyerDropProductsSection(
                products: weeklyDropProducts,
                isLockedPreview: false,
                lockedMessage: nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.bottom, TopLevelHeaderMetrics.dropBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var buyerThursdayPreviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DropLayoutMetrics.buyerHeaderStackSpacing) {
                SnowfallTitleContainer(cornerRadius: 28, horizontalPadding: 18, verticalPadding: 5, flakeCount: 82) {
                    Image("WeeklyDropTitle")
                        .resizable()
                        .scaledToFit()
                        .frame(height: DropLayoutMetrics.buyerTitleHeight)
                        .padding(.bottom, DropLayoutMetrics.buyerTitleBottomTuck)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DropLayoutMetrics.buyerTitleCardOverlap)

                weeklyDropPreviewBadge
                WeeklyDropBoardCard(state: buyerThursdayPreviewState, now: countdownNow)
            }
            .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
            .padding(.top, DropLayoutMetrics.buyerContentTopInset)

            buyerDropProductsSection(
                products: weeklyDropProducts,
                isLockedPreview: true,
                lockedMessage: "Preview only until Friday 12:00 AM"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.bottom, TopLevelHeaderMetrics.dropBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Buyer Inactive Drop

    @ViewBuilder
    private var buyerInactiveDropContent: some View {
        VStack(spacing: TBTheme.spacingMD + 2) {
            SnowfallTitleContainer(cornerRadius: 28, horizontalPadding: 18, verticalPadding: 8, flakeCount: 82) {
                Image("WeeklyDropTitle")
                    .resizable()
                    .scaledToFit()
                    .frame(height: DropLayoutMetrics.buyerTitleHeight)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
            .padding(.top, TopLevelHeaderMetrics.dropTopInset)

            Spacer(minLength: DropLayoutMetrics.buyerInactiveHeroTopSpacing)

            VStack(spacing: 0) {
                Text(
                    DropCountdown.inactiveBuyerNextDropHeadline(
                        nextDropAtISO: effectiveDropResponse?.nextDropAt,
                        now: countdownNow,
                        currentDrop: effectiveDropResponse
                    )
                )
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .tracking(-0.6)
                .foregroundStyle(TBTheme.frostTitleGradient)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .lineLimit(3)
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.vertical, TBTheme.spacingXL)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(0.52), lineWidth: 1)
            )
            .shadow(color: TBTheme.deepSky.opacity(0.1), radius: 12, y: 4)

            if !buyerPreviewDropProducts.isEmpty && !isUsingWeeklyDropPreview {
                VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                    Text("Preview examples")
                        .font(.tbSectionTitle)
                        .foregroundStyle(TBTheme.frostTitleGradient)
                    Text("Mock buyer view of how weekly drop products will appear.")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)

                    ForEach(buyerPreviewDropProducts) { product in
                        Button {
                            selectedDropProduct = resolvedProduct(for: product)
                        } label: {
                            DropProductRow(
                                product: product,
                                sellerDisplayName: displayName(forSellerId: product.sellerId)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: DropLayoutMetrics.buyerInactiveHeroBottomSpacing)
        }
        .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
        .padding(.top, TopLevelHeaderMetrics.dropTopInset)
        .padding(.bottom, TopLevelHeaderMetrics.dropBottomInset)
    }

    @ViewBuilder
    private var buyerPreviewDropContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DropLayoutMetrics.buyerHeaderStackSpacing) {
                SnowfallTitleContainer(cornerRadius: 28, horizontalPadding: 18, verticalPadding: 5, flakeCount: 82) {
                    Image("WeeklyDropTitle")
                        .resizable()
                        .scaledToFit()
                        .frame(height: DropLayoutMetrics.buyerTitleHeight)
                        .padding(.bottom, DropLayoutMetrics.buyerTitleBottomTuck)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DropLayoutMetrics.buyerTitleCardOverlap)

                weeklyDropPreviewBadge
                WeeklyDropBoardCard(state: buyerPreviewBoardState, now: countdownNow)
            }
            .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
            .padding(.top, DropLayoutMetrics.buyerContentTopInset)

            buyerDropProductsSection(
                products: buyerPreviewDropProducts,
                isLockedPreview: false,
                lockedMessage: nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.bottom, TopLevelHeaderMetrics.dropBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Seller Hub

    @ViewBuilder
    private var sellerDropHubContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DropLayoutMetrics.sellerHeaderSpacing) {
                SnowfallTitleContainer(cornerRadius: 28, horizontalPadding: 18, verticalPadding: 6, flakeCount: 82) {
                    Image("WeeklyDropTitle")
                        .resizable()
                        .scaledToFit()
                        .frame(height: DropLayoutMetrics.sellerTitleHeight)
                        .padding(.bottom, DropLayoutMetrics.sellerTitleBottomTuck)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                weeklyDropPreviewBadge
                sellerHeroCard

                if let errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.orange)

                        Text(errorMessage)
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 0.8)
                    )
                }

            }
            .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
            .padding(.top, DropLayoutMetrics.sellerContentTopInset)
            .padding(.bottom, 4)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                    if submissionWindowOpen && !sellerSubmissionProducts.isEmpty {
                        sellerSubmissionSection
                    }

                    if isActive && !weeklyDropProducts.isEmpty {
                        VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                            HStack(alignment: .center, spacing: 8) {
                                Text("Live this weekend")
                                    .font(.tbSectionTitle)
                                    .foregroundStyle(TBTheme.frostTitleGradient)
                                Spacer(minLength: 8)
                                if let endsAt = effectiveDropResponse?.endsAt {
                                    Text(DropCountdown.timeLeft(until: endsAt))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(TBTheme.accent, in: Capsule())
                                }
                            }

                            ForEach(weeklyDropProducts) { product in
                                Button {
                                    selectedDropProduct = resolvedProduct(for: product)
                                } label: {
                                    DropProductRow(
                                        product: product,
                                        sellerDisplayName: displayName(forSellerId: product.sellerId),
                                        isCompact: true
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if sellerSubmissionProducts.isEmpty && sellerDisplayHistoryWeeks.isEmpty && (!isActive || weeklyDropProducts.isEmpty) {
                        VStack(spacing: 12) {
                            Image("Logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 104, height: 66)
                                .accessibilityHidden(true)

                            Text("Your weekly lineup will appear here")
                                .font(.tbBodyStrong)
                                .foregroundStyle(TBTheme.deepSky)

                            Text("Prep featured products for Friday, then review and refine them in your dedicated drop workspace.")
                                .font(.tbCaption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
                        )
                    }

                    sellerHistorySection
                }
                .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
                .padding(.top, 0)
                .padding(.bottom, TBTheme.spacingSM)
            }
            .refreshable {
                await loadDrop()
                await sellerSubscription.refresh()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var sellerHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Seller Exclusive", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.88), in: Capsule())

                if submissionWindowOpen {
                    Label("Window Open", systemImage: "clock.badge.checkmark")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.88), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(sellerStatusTitle)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(sellerStatusSubtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    if sellerHasWeeklyDropAccess {
                        await MainActor.run { showDropSubmit = true }
                    } else {
                        await sellerSubscription.refresh()
                        await sellerSubscription.purchaseMembership()
                        if sellerSubscription.hasActiveSubscription {
                            await MainActor.run { showDropSubmit = true }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(primarySellerCTA)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.bannerCTAForeground)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TBTheme.bannerCTAForeground.opacity(0.86))
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.34),
                                    TBTheme.skyLight.opacity(0.18),
                                    TBTheme.icyBlue.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.78),
                                    TBTheme.skyBlue.opacity(0.28),
                                    TBTheme.deepSky.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(TBTheme.dropBannerGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            LinearGradient(
                colors: [.white.opacity(0.22), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.22), radius: 16, y: 8)
    }

    private var sellerSubmissionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text("Your submissions")
                    .font(.tbSectionTitle)
                    .foregroundStyle(TBTheme.frostTitleGradient)

                Spacer(minLength: 8)

                Text("\(sellerSubmissionProducts.count) item\(sellerSubmissionProducts.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TBTheme.deepSky)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.86), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.16), lineWidth: 0.8)
                    )
            }

            Text("This is the lineup buyers will see when your weekly drop goes live.")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -2)

            ForEach(sellerSubmissionProducts) { product in
                Button {
                    selectedDropProduct = resolvedProduct(for: product)
                } label: {
                    DropProductRow(
                        product: product,
                        sellerDisplayName: displayName(forSellerId: product.sellerId),
                        isCompact: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sellerHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("History")
                    .font(.tbSectionTitle)
                    .foregroundStyle(TBTheme.frostTitleGradient)

                Spacer(minLength: 8)

                Text(sellerDisplayHistoryWeeks.isEmpty ? "No past drops" : "\(sellerDisplayHistoryWeeks.count) weekend\(sellerDisplayHistoryWeeks.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TBTheme.deepSky)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.86), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.16), lineWidth: 0.8)
                    )
            }

            Text("Past weekend lineups stay organized by date so sellers can review what was posted and what sold.")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -2)

            if sellerDisplayHistoryWeeks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No completed Weekly Drops yet", systemImage: "clock.arrow.circlepath")
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)

                    Text("After a weekend drop closes on Sunday night, that lineup will appear here as history.")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sellerDisplayHistoryWeeks) { week in
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    selectedHistoryWeekId = week.weekId
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(historyWeekendRangeText(for: week))
                                        .font(.caption.weight(.semibold))
                                    Text("\(week.postedCount) posted • \(week.soldCount) sold")
                                        .font(.caption2.weight(.medium))
                                        .opacity(0.82)
                                }
                                .foregroundStyle(selectedHistoryWeek?.weekId == week.weekId ? .white : TBTheme.deepSky)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(
                                    Group {
                                        if selectedHistoryWeek?.weekId == week.weekId {
                                            Capsule(style: .continuous).fill(TBTheme.dropBannerGradient)
                                        } else {
                                            Capsule(style: .continuous).fill(.white.opacity(0.86))
                                        }
                                    }
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(TBTheme.skyBlue.opacity(0.16), lineWidth: 0.8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if let selectedHistoryWeek {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(historyWeekendRangeText(for: selectedHistoryWeek))
                                .font(.tbBodyStrong)
                                .foregroundStyle(TBTheme.deepSky)

                            Spacer(minLength: 8)

                            Text("\(selectedHistoryWeek.postedCount) posted • \(selectedHistoryWeek.soldCount) sold")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TBTheme.icyBlue)
                        }

                        ForEach(selectedHistoryWeek.products) { product in
                            Button {
                                selectedDropProduct = resolvedProduct(for: product)
                            } label: {
                                DropProductRow(
                                    product: product,
                                    sellerDisplayName: displayName(forSellerId: product.sellerId),
                                    isCompact: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 0.8)
                    )
                }
            }
        }
        .padding(.top, TBTheme.spacingSM)
    }

    private var sellerStatusTitle: String {
        if isActive {
            return "Weekly Drop Is Live"
        }
        if submissionWindowOpen {
            return "Submissions Are Open"
        }
        return "Get Ready For Friday"
    }

    private var sellerStatusSubtitle: String {
        if !sellerHasWeeklyDropAccess {
            return "When the window is open, you’ll build your drop from the seller workspace. Submitting needs an active seller plan. See Settings, or you’ll be prompted if you try to add or submit without one."
        }
        if isActive {
            return "Your premium lineup is live this weekend. Weekly Drop only includes items priced over $10."
        }
        if submissionWindowOpen {
            return "Submit products over $10 on Thursday evening so they go live automatically at Friday 12:00 AM ET."
        }
        if !sellerSubmissionProducts.isEmpty {
            return "Thursday uploads are closed. Your drop lineup now appears in History for date-based review."
        }
        if let next = effectiveSellerSubmissions?.nextDropAt {
            return "The next submission window opens \(DropCountdown.timeLeft(until: next)). New uploads reopen Thursday at 5:00 PM ET."
        }
        return "The next submission window opens Thursday at 5:00 PM ET. New uploads return during that submission window."
    }

    private var primarySellerCTA: String {
        if submissionWindowOpen {
            return sellerSubmissionProducts.isEmpty ? "Add Your First Drop Item" : "Edit Your Drop Lineup"
        }
        return sellerSubmissionProducts.isEmpty ? "View Drop Workspace" : "Review This Week's Drop"
    }

    private var sellerActionSubtitle: String {
        if submissionWindowOpen {
            return sellerSubmissionProducts.isEmpty
                ? "Add premium products over $10 during the Thursday evening upload window."
                : "Update this week's premium products before Thursday at 11:59 PM ET."
        }
        return sellerSubmissionProducts.isEmpty
            ? "Thursday uploads are closed right now. New submissions return during the next Thursday window."
            : "Review and edit your current lineup. New photo and video uploads reopen on Thursday."
    }

    private var sellerActionIcon: String {
        if submissionWindowOpen {
            return sellerSubmissionProducts.isEmpty ? "sparkles" : "shippingbox.fill"
        }
        return sellerSubmissionProducts.isEmpty ? "calendar.badge.clock" : "square.and.pencil"
    }

    // MARK: - Load

    private func loadDropIfNeeded(force: Bool = false) async {
        let now = Date()
        guard force || now.timeIntervalSince(lastDropLoad) > 45 else { return }
        await loadDrop()
    }

    private func refreshSubscriptionIfNeeded(force: Bool = false) async {
        let now = Date()
        guard force || now.timeIntervalSince(lastSubscriptionRefresh) > 45 else { return }
        lastSubscriptionRefresh = now
        await sellerSubscription.refresh()
    }

    private func loadDrop() async {
        guard !isDropLoadInFlight else { return }
        isDropLoadInFlight = true
        defer { isDropLoadInFlight = false }
        lastDropLoad = Date()
        isLoading = true
        errorMessage = nil

        do {
            dropResponse = try await DropAPI.currentDrop()
        } catch {
            errorMessage = "We couldn't load the weekly drop right now."
        }

        if isSeller {
            do {
                sellerSubmissions = try await DropAPI.mySubmissions(sellerId: sellerId)
            } catch {
                errorMessage = "We couldn't load your weekly drop submissions."
            }

            do {
                sellerDropHistory = try await DropAPI.history(sellerId: sellerId)
                if selectedHistoryWeekId == nil {
                    selectedHistoryWeekId = sellerDropHistory?.weeks.first?.weekId
                }
            } catch {
                if sellerDropHistory == nil {
                    sellerDropHistory = SellerDropHistoryResponse(sellerId: sellerId, weeks: [])
                }
            }
        }

        isLoading = false
    }

    private func resolvedProduct(for dropProduct: DropProduct) -> Product {
        if let storefrontMatch = storefrontProducts.first(where: { $0.id == dropProduct.id }) {
            return storefrontMatch
        }

        return Product(
            id: dropProduct.id,
            sellerId: dropProduct.sellerId,
            name: dropProduct.name,
            priceCents: dropProduct.priceCents,
            category: resolvedCategory(for: dropProduct.category),
            imageNames: dropProduct.imageURLs,
            demoVideoURL: Product.mediaURL(for: dropProduct.demoVideoURL),
            productionPreviewURL: Product.mediaURL(for: dropProduct.productionPreviewURL),
            pageViewCount: 0,
            favoriteCount: 0,
            material: dropProduct.material,
            productionNote: dropBuyerStatusNote(for: dropProduct),
            durabilityNote: dropProduct.durabilityNote,
            careWarnings: dropProduct.careWarnings,
            shipsInDays: min(dropProduct.shipsInMinDays, dropProduct.shipsInMaxDays)...max(dropProduct.shipsInMinDays, dropProduct.shipsInMaxDays),
            previousPriceCents: dropProduct.previousPriceCents
        )
    }

    private func dropBuyerStatusNote(for dropProduct: DropProduct) -> String {
        let headline = dropProduct.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        if !headline.isEmpty {
            return headline
        }

        let story = dropProduct.story.trimmingCharacters(in: .whitespacesAndNewlines)
        if !story.isEmpty {
            return story
        }

        return "Printed fresh when you order"
    }

    private func resolvedCategory(for rawCategory: String) -> Category {
        Category(rawValue: rawCategory) ?? .home
    }

    private func displayName(forSellerId sellerId: String) -> String {
        sellerProfilesByID[sellerId]?.displayName ?? SellerProfile.fallbackDisplayName(forSellerId: sellerId)
    }

    private func historyWeekendRangeText(for week: SellerDropHistoryWeek) -> String {
        guard
            let start = previewDateFormatter.date(from: week.startsAt),
            let end = previewDateFormatter.date(from: week.endsAt)
        else {
            return week.weekId
        }

        let startText = start.formatted(.dateTime.month(.abbreviated).day())
        let endText = end.formatted(.dateTime.month(.abbreviated).day())
        return "\(startText)-\(endText)"
    }

    private var weeklyDropPreviewMenu: some View {
        Menu {
            Picker("Weekly Drop Preview", selection: $weeklyDropPreviewModeRaw) {
                ForEach(WeeklyDropPreviewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName)
                        .tag(mode.rawValue)
                }
            }
        } label: {
            Label("Preview", systemImage: isUsingWeeklyDropPreview ? "eye.fill" : "eye")
                .labelStyle(.iconOnly)
                .foregroundStyle(isUsingWeeklyDropPreview ? TBTheme.skyBlue : .secondary)
        }
        .accessibilityLabel(
            isUsingWeeklyDropPreview
                ? "Weekly Drop preview mode: \(weeklyDropPreviewMode.title)"
                : "Weekly Drop preview menu"
        )
    }

    @ViewBuilder
    private var weeklyDropPreviewBadge: some View {
        if isUsingWeeklyDropPreview {
            Label(weeklyDropPreviewMode.title, systemImage: weeklyDropPreviewMode.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TBTheme.deepSky)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.86), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(TBTheme.skyBlue.opacity(0.18), lineWidth: 0.9)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var previewCurrentDropResponse: CurrentDropResponse? {
        guard isUsingWeeklyDropPreview else { return nil }

        let startDate: Date
        let endDate: Date
        let nextDropAt: Date?
        let isActivePreview: Bool

        switch weeklyDropPreviewMode {
        case .liveData:
            return nil
        case .beforeFriday:
            startDate = previewAnchorNow.addingTimeInterval(6 * 60 * 60)
            endDate = startDate.addingTimeInterval((72 * 60 * 60) - 1)
            nextDropAt = startDate
            isActivePreview = false
        case .thursdayPreview:
            startDate = previewAnchorNow.addingTimeInterval(6 * 60 * 60)
            endDate = startDate.addingTimeInterval((72 * 60 * 60) - 1)
            nextDropAt = startDate
            isActivePreview = false
        case .fridaySubmitting:
            startDate = previewAnchorNow.addingTimeInterval(-2 * 60 * 60)
            endDate = startDate.addingTimeInterval((72 * 60 * 60) - 1)
            nextDropAt = nil
            isActivePreview = true
        case .weekendLive:
            startDate = previewAnchorNow.addingTimeInterval(-18 * 60 * 60)
            endDate = startDate.addingTimeInterval((72 * 60 * 60) - 1)
            nextDropAt = nil
            isActivePreview = true
        case .closed:
            startDate = previewAnchorNow.addingTimeInterval(-5 * 24 * 60 * 60)
            endDate = previewAnchorNow.addingTimeInterval(-2 * 24 * 60 * 60)
            nextDropAt = previewAnchorNow.addingTimeInterval(36 * 60 * 60)
            isActivePreview = false
        }

        return CurrentDropResponse(
            active: isActivePreview,
            weekId: "preview-\(weeklyDropPreviewMode.rawValue)",
            startsAt: previewDateFormatter.string(from: startDate),
            endsAt: previewDateFormatter.string(from: endDate),
            products: previewProducts(startDate: startDate),
            nextDropAt: nextDropAt.map(previewDateFormatter.string(from:))
        )
    }

    private var previewSellerSubmissions: SellerSubmissionsResponse? {
        guard isUsingWeeklyDropPreview else { return nil }

        let resolvedSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "seller_preview"
            : sellerId

        let baseProducts = Array(buyerPreviewDropProducts.prefix(3)).enumerated().map { entry in
            let product = entry.element
            return DropProduct(
                id: "seller-preview-\(weeklyDropPreviewMode.rawValue)-\(entry.offset)-\(product.id)",
                sellerId: resolvedSellerId,
                name: product.name,
                priceCents: product.priceCents,
                previousPriceCents: product.previousPriceCents,
                category: product.category,
                imageURLs: product.imageURLs,
                demoVideoURL: product.demoVideoURL,
                productionPreviewURL: product.productionPreviewURL,
                headline: product.headline,
                story: product.story,
                bestUseCase: product.bestUseCase,
                material: product.material,
                durabilityNote: product.durabilityNote,
                careWarnings: product.careWarnings,
                shipsInMinDays: product.shipsInMinDays,
                shipsInMaxDays: product.shipsInMaxDays,
                approvalStatus: product.approvalStatus,
                reviewNotes: product.reviewNotes,
                reviewedAt: product.reviewedAt,
                submittedAt: product.submittedAt,
                slotNumber: entry.offset + 1
            )
        }

        return SellerSubmissionsResponse(
            sellerId: resolvedSellerId,
            weekId: "preview-\(weeklyDropPreviewMode.rawValue)",
            isActive: weeklyDropPreviewMode == .thursdayPreview,
            nextDropAt: previewCurrentDropResponse?.nextDropAt,
            slotsUsed: min(baseProducts.count, DropConstants.maxSlotsPerSeller),
            slotsMax: DropConstants.maxSlotsPerSeller,
            products: baseProducts
        )
    }

    private func previewProducts(startDate: Date) -> [DropProduct] {
        let baseProducts = Array(buyerPreviewDropProducts.prefix(10))
        let submissionOffsets: [TimeInterval]

        switch weeklyDropPreviewMode {
        case .beforeFriday:
            submissionOffsets = [-2_400, -2_100, -1_800, -1_500, -1_200, -900, -600, -300, -180, -60]
        case .thursdayPreview:
            submissionOffsets = [-2_400, -2_100, -1_800, -1_500, -1_200, -900, -600, -300, -180, -60]
        case .fridaySubmitting:
            submissionOffsets = [-2_400, -1_800, -900, -240, 20, 45, 75, 110, 150, 210]
        case .weekendLive:
            submissionOffsets = [-70_000, -68_000, -66_000, -64_000, -62_000, -60_000, -58_000, -56_000, -54_000, -52_000]
        case .closed:
            submissionOffsets = [-120_000, -118_000, -116_000, -114_000, -112_000, -110_000, -108_000, -106_000, -104_000, -102_000]
        case .liveData:
            submissionOffsets = []
        }

        return Array(zip(baseProducts, submissionOffsets)).enumerated().map { index, pair in
            let product = pair.0
            let submittedAt = startDate.addingTimeInterval(pair.1)
            return DropProduct(
                id: "preview-\(weeklyDropPreviewMode.rawValue)-\(index)-\(product.id)",
                sellerId: product.sellerId,
                name: product.name,
                priceCents: product.priceCents,
                previousPriceCents: product.previousPriceCents,
                category: product.category,
                imageURLs: product.imageURLs,
                demoVideoURL: product.demoVideoURL,
                productionPreviewURL: product.productionPreviewURL,
                headline: product.headline,
                story: product.story,
                bestUseCase: product.bestUseCase,
                material: product.material,
                durabilityNote: product.durabilityNote,
                careWarnings: product.careWarnings,
                shipsInMinDays: product.shipsInMinDays,
                shipsInMaxDays: product.shipsInMaxDays,
                approvalStatus: weeklyDropPreviewMode == .weekendLive ? .live : .approved,
                reviewNotes: product.reviewNotes,
                reviewedAt: product.reviewedAt,
                submittedAt: previewDateFormatter.string(from: submittedAt),
                slotNumber: index + 1
            )
        }
    }

    @ViewBuilder
    private func buyerDropProductsSection(
        products: [DropProduct],
        isLockedPreview: Bool,
        lockedMessage: String?
    ) -> some View {
        let pageCount = max(
            Int(ceil(Double(products.count) / Double(BuyerDropPagedList.pageSize))),
            1
        )
        let showsPagination = products.count > BuyerDropPagedList.pageSize

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("Weekend specials")
                    .font(.tbSectionTitle)
                    .foregroundStyle(TBTheme.frostTitleGradient)

                Spacer(minLength: 8)

                if showsPagination {
                    HStack(spacing: 6) {
                        Button {
                            buyerProductsPage = max(buyerProductsPage - 1, 0)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .disabled(buyerProductsPage <= 0)
                        .accessibilityLabel("Previous page")

                        Text("\(buyerProductsPage + 1) / \(pageCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TBTheme.deepSky)
                            .monospacedDigit()
                            .accessibilityLabel("Page \(buyerProductsPage + 1) of \(pageCount)")

                        Button {
                            buyerProductsPage = min(buyerProductsPage + 1, max(pageCount - 1, 0))
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .disabled(buyerProductsPage >= pageCount - 1)
                        .accessibilityLabel("Next page")
                    }
                    .foregroundStyle(TBTheme.deepSky)
                }
            }
            .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)

            BuyerDropPagedList(
                products: products,
                currentPage: $buyerProductsPage,
                isLockedPreview: isLockedPreview,
                lockedMessage: lockedMessage,
                sellerDisplayName: displayName(forSellerId:)
            ) { product in
                selectedDropProduct = resolvedProduct(for: product)
            }
            .padding(.horizontal, TopLevelHeaderMetrics.sharedHorizontalInset)
        }
    }
}

// MARK: - Drop Product Row (uses DropProduct instead of Product)

private struct BuyerDropPagedList: View {
    static let pageSize = 5

    let products: [DropProduct]
    @Binding var currentPage: Int
    let isLockedPreview: Bool
    let lockedMessage: String?
    let sellerDisplayName: (String) -> String
    let onSelect: (DropProduct) -> Void

    private var pageCount: Int {
        max(Int(ceil(Double(products.count) / Double(Self.pageSize))), 1)
    }

    private var visibleProducts: [DropProduct] {
        let safePage = min(currentPage, max(pageCount - 1, 0))
        let start = safePage * Self.pageSize
        let end = min(start + Self.pageSize, products.count)
        guard start < end else { return [] }
        return Array(products[start..<end])
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: TBTheme.spacingMD) {
                ForEach(visibleProducts) { product in
                    Button {
                        guard !isLockedPreview else { return }
                        onSelect(product)
                    } label: {
                        DropProductRow(
                            product: product,
                            sellerDisplayName: sellerDisplayName(product.sellerId),
                            isLockedPreview: isLockedPreview,
                            lockedMessage: lockedMessage
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLockedPreview)
                }
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: products.count) { _, _ in
            currentPage = min(currentPage, max(pageCount - 1, 0))
        }
    }
}

private struct DropProductRow: View {
    let product: DropProduct
    let sellerDisplayName: String
    var isLockedPreview = false
    var lockedMessage: String? = nil
    /// Tighter layout for the seller Weekly Drop hub only (submissions + live weekend rows).
    var isCompact = false

    private var thumbnailSize: CGFloat { isCompact ? 52 : 64 }
    private var rowHorizontalPadding: CGFloat { isCompact ? 11 : 14 }
    private var rowVerticalPadding: CGFloat { isCompact ? 6 : 10 }
    private var rowCornerRadius: CGFloat { isCompact ? 18 : 20 }
    private var textStackSpacing: CGFloat { isCompact ? 2 : 4 }
    private var creatorColumnMaxWidth: CGFloat { isCompact ? 88 : 120 }

    private var shipsText: String {
        "\(min(product.shipsInMinDays, product.shipsInMaxDays))-\(max(product.shipsInMinDays, product.shipsInMaxDays)) days"
    }

    private var mediaSignals: [(String, String)] {
        var signals: [(String, String)] = []
        if product.demoVideoURL != nil {
            signals.append(("play.rectangle.fill", "Creator clip"))
        }
        if let previousPriceCents = product.previousPriceCents,
           previousPriceCents > product.priceCents {
            signals.append(("tag.fill", "Price drop"))
        }
        return signals
    }

    var body: some View {
        HStack(alignment: .top, spacing: isCompact ? 8 : 10) {
            StorefrontImageView(reference: product.primaryImageReference) {
                RoundedRectangle(cornerRadius: TBTheme.radiusMD)
                    .fill(TBTheme.heroGradient)
                    .overlay {
                        Image(systemName: "cube.fill")
                            .font(isCompact ? .title3 : .title2)
                            .foregroundStyle(TBTheme.skyBlue)
                    }
            }
            .frame(width: thumbnailSize, height: thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: TBTheme.radiusMD, style: .continuous))

            VStack(alignment: .leading, spacing: textStackSpacing) {
                if isLockedPreview {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(lockedMessage ?? "Locked until Friday")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(TBTheme.deepSky)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.92), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
                    )
                } else if !mediaSignals.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(mediaSignals.enumerated()), id: \.offset) { _, signal in
                            Label(signal.1, systemImage: signal.0)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(TBTheme.deepSky)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.92), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
                                )
                        }
                    }
                }

                Text(product.name)
                    .font(isCompact ? .system(size: 14, weight: .semibold, design: .rounded) : .tbProductTitleSM)
                    .tbProductNameTitleStyle()
                    .lineLimit(isCompact ? 1 : 2)

                Text(product.displayHeadline)
                    .font(isCompact ? .caption2 : .tbCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(isCompact ? 1 : 2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Money.format(cents: product.priceCents))
                        .font(isCompact ? .system(size: 14, weight: .semibold, design: .rounded) : .tbProductPriceSM)
                        .foregroundStyle(.primary.opacity(0.82))

                    if let previousPriceCents = product.previousPriceCents,
                       previousPriceCents > product.priceCents {
                        Text(Money.format(cents: previousPriceCents))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .strikethrough()
                    }
                }

                Text("\(product.material) • \(shipsText)")
                    .font(isCompact ? .caption2 : .caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: isCompact ? 1 : 2) {
                Text("Creator")
                    .font(.system(size: isCompact ? 9 : 10))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(sellerDisplayName)
                    .font(isCompact ? .caption2.weight(.medium) : .caption.weight(.medium))
                    .foregroundStyle(TBTheme.skyBlue)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(isCompact ? 1 : 2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: creatorColumnMaxWidth, alignment: .trailing)
        }
        .padding(.horizontal, rowHorizontalPadding)
        .padding(.vertical, rowVerticalPadding)
        .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
        .blur(radius: isLockedPreview ? 2.8 : 0)
        .overlay(alignment: .center) {
            if isLockedPreview {
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .fill(.white.opacity(0.06))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: TBTheme.deepSky.opacity(isCompact ? 0.06 : 0.08), radius: isCompact ? 6 : 10, y: isCompact ? 2 : 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isLockedPreview
                ? "\(product.name), \(product.displayHeadline), preview only until Friday, \(Money.format(cents: product.priceCents)), \(product.material), ships in \(shipsText), \(sellerDisplayName)"
                : "\(product.name), \(product.displayHeadline), \(Money.format(cents: product.priceCents)), \(product.material), ships in \(shipsText), \(sellerDisplayName)"
        )
    }
}

