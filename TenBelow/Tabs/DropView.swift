//
//  DropView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import Combine

struct DropView: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore
    @AppStorage("userRole") private var userRole = ""
    @AppStorage("sellerSellerId") private var sellerId = ""
    @AppStorage("sellerPreviewMode") private var sellerPreviewMode = false
    @State private var showCart = false
    @State private var dropResponse: CurrentDropResponse?
    @State private var sellerSubmissions: SellerSubmissionsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showSubscriptionCenter = false
    @State private var showDropSubmit = false
    private var isActive: Bool { dropResponse?.active == true }
    private var dropProducts: [DropProduct] { dropResponse?.products ?? [] }
    private var weeklyDropProducts: [DropProduct] {
        dropProducts.filter { $0.priceCents > 1_000 }
    }
    private var isSeller: Bool { userRole == "seller" && !sellerId.isEmpty }
    private var sellerSubmissionProducts: [DropProduct] { sellerSubmissions?.products ?? [] }
    private var slotsUsed: Int { sellerSubmissions?.slotsUsed ?? 0 }
    private var slotsMax: Int { sellerSubmissions?.slotsMax ?? DropConstants.maxSlotsPerSeller }
    private var slotsRemaining: Int { max(slotsMax - slotsUsed, 0) }
    private var submissionWindowOpen: Bool { sellerSubmissions?.isActive == true }

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if isSeller {
                        sellerDropHubContent
                    } else if isActive && !weeklyDropProducts.isEmpty {
                        buyerActiveDropContent
                    } else {
                        buyerInactiveDropContent
                    }
                }

                if isLoading {
                    AppLoadingOverlay(
                        title: "Loading Drop",
                        subtitle: "Checking this week's featured products."
                    )
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .background(TBTheme.cloudWhite)
            .navigationTitle("")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                DropSubmitView()
            }
            .sheet(isPresented: $showSubscriptionCenter) {
                SellerSubscriptionView()
            }
            .task {
                await loadDrop()
                await sellerSubscription.refresh()
            }
            .refreshable {
                await loadDrop()
                await sellerSubscription.refresh()
            }
        }
    }

    // MARK: - Buyer Active Drop

    @ViewBuilder
    private var buyerActiveDropContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TBTheme.spacingMD) {

                SnowfallTitleContainer(cornerRadius: 28, horizontalPadding: 18, verticalPadding: 12, flakeCount: 82) {
                    Image("WeeklyDropTitle")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 176)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Hero banner
                VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                            .fill(TBTheme.dropBannerGradient)
                            .frame(height: 180)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("This week's drop")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                            Text("Friday-Sunday only • Over $10 • Limited release")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(TBTheme.spacingLG)
                    }

                    if let resp = dropResponse {
                        HStack {
                            Text(DropCountdown.timeLeft(until: resp.endsAt))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(TBTheme.accent)
                                .clipShape(Capsule())

                            Spacer()

                            Text("\(weeklyDropProducts.count) product\(weeklyDropProducts.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text("Premium 3D-printed products from sellers across TenBelow. Weekly Drop includes items priced above $10.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                // Drop products
                VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                    Text("This week's items")
                        .font(.tbSectionTitle)
                        .foregroundStyle(TBTheme.frostTitleGradient)

                    ForEach(weeklyDropProducts) { product in
                        DropProductRow(product: product)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 0)
            .padding(.bottom)
        }
    }

    // MARK: - Buyer Inactive Drop

    @ViewBuilder
    private var buyerInactiveDropContent: some View {
        VStack(spacing: TBTheme.spacingMD) {
            SnowfallTitleContainer(cornerRadius: 28, horizontalPadding: 18, verticalPadding: 12, flakeCount: 82) {
                Image("WeeklyDropTitle")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 176)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 0)

            Spacer(minLength: 10)

            Image(systemName: "flame")
                .font(.system(size: 56))
                .foregroundStyle(TBTheme.skyBlue.opacity(0.4))

            Text("No drop this weekend")
                .font(.tbCardTitle)
                .foregroundStyle(TBTheme.frostTitleGradient)

            if let next = dropResponse?.nextDropAt {
                Text("Next drop opens \(DropCountdown.timeLeft(until: next))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Sellers can submit eligible products every Friday through Sunday.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 0)
        .padding(.bottom)
    }

    // MARK: - Seller Hub

    @ViewBuilder
    private var sellerDropHubContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                SnowfallTitleContainer(cornerRadius: 28, horizontalPadding: 18, verticalPadding: 8, flakeCount: 82) {
                    Image("WeeklyDropTitle")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 132)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                sellerStatusCard

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                sellerActionsSection
            }
            .padding(.horizontal)
            .padding(.top, 0)
            .padding(.bottom, TBTheme.spacingSM)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                    if !sellerSubmissionProducts.isEmpty {
                        VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                            Text("Your submissions")
                                .font(.tbSectionTitle)
                                .foregroundStyle(TBTheme.frostTitleGradient)

                            ForEach(sellerSubmissionProducts) { product in
                                DropProductRow(product: product)
                            }
                        }
                    }

                    if isActive && !weeklyDropProducts.isEmpty {
                        VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
                            HStack(alignment: .center, spacing: 8) {
                                Text("Live this weekend")
                                    .font(.tbSectionTitle)
                                    .foregroundStyle(TBTheme.frostTitleGradient)
                                Spacer(minLength: 8)
                                if let endsAt = dropResponse?.endsAt {
                                    Text(DropCountdown.timeLeft(until: endsAt))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(TBTheme.accent, in: Capsule())
                                }
                            }

                            ForEach(weeklyDropProducts.prefix(2)) { product in
                                DropProductRow(product: product)
                            }
                        }
                    }

                    if sellerSubmissionProducts.isEmpty && (!isActive || weeklyDropProducts.isEmpty) {
                        Text("Your submissions and live drop products appear here.")
                            .font(.tbBody)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, TBTheme.spacingMD)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Status icon in the blue card: flame “lights up” when the weekly drop is live for buyers.
    @ViewBuilder
    private var sellerStatusTrailingBadge: some View {
        let iconName = isActive ? "flame.fill" : (submissionWindowOpen ? "shippingbox.fill" : "calendar")

        if isActive {
            Image(systemName: iconName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.98, blue: 0.55),
                            Color(red: 1.0, green: 0.65, blue: 0.2),
                            Color(red: 1.0, green: 0.35, blue: 0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.orange.opacity(0.95), radius: 4, y: 0)
                .shadow(color: Color.yellow.opacity(0.75), radius: 12, y: 0)
                .shadow(color: Color.red.opacity(0.45), radius: 18, y: 2)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.orange.opacity(0.22))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .yellow.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .symbolEffect(.pulse, options: .repeating.speed(0.45), value: isActive)
        } else {
            Image(systemName: iconName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(14)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var sellerStatusCard: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(sellerStatusTitle)
                        .font(.tbTitle)
                        .foregroundStyle(.white)

                    Text(sellerStatusSubtitle)
                        .font(.tbBody)
                        .foregroundStyle(.white.opacity(0.84))
                        .lineSpacing(2)
                }

                Spacer()

                sellerStatusTrailingBadge
            }

            HStack(spacing: 12) {
                sellerInfoPill(title: "Used", value: "\(slotsUsed)/\(slotsMax)")
                sellerInfoPill(title: "Open Slots", value: "\(slotsRemaining)")

                if let next = sellerSubmissions?.nextDropAt, !submissionWindowOpen && !isActive {
                    sellerInfoPill(title: "Next Window", value: DropCountdown.timeLeft(until: next))
                } else if let endsAt = dropResponse?.endsAt, isActive {
                    sellerInfoPill(title: "Ends In", value: DropCountdown.timeLeft(until: endsAt))
                }
            }
        }
        .padding(.horizontal, TBTheme.spacingMD)
        .padding(.vertical, TBTheme.spacingMD)
        .background(TBTheme.dropBannerGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.18), radius: 10, y: 3)
    }

    private func sellerInfoPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sellerActionsSection: some View {
        Button {
            if sellerPreviewMode || sellerSubscription.hasActiveSubscription {
                showDropSubmit = true
            } else {
                showSubscriptionCenter = true
            }
        } label: {
            HStack(spacing: TBTheme.spacingMD) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.16))
                        .frame(width: 48, height: 48)

                    Image(systemName: sellerActionIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(primarySellerCTA)
                        .font(.tbHeadline)
                        .foregroundStyle(.white)

                    Text(sellerActionSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(10)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .padding(.horizontal, TBTheme.spacingMD)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TBTheme.dropBannerGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: TBTheme.deepSky.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
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
        if isActive {
            return "Buyers can shop this week's premium drop Friday-Sunday. Weekly Drop only includes items priced over $10."
        }
        if submissionWindowOpen {
            return "Submit products over $10 for this Friday-Sunday drop. New submissions replace the previous lineup each week."
        }
        if let next = sellerSubmissions?.nextDropAt {
            return "The next submission window opens \(DropCountdown.timeLeft(until: next)). Prep your premium listings now so they're ready for the next Friday-Sunday drop."
        }
        return "The next submission window opens Friday. Prep your premium listings now so they're ready for the next Friday-Sunday drop."
    }

    private var primarySellerCTA: String {
        if submissionWindowOpen {
            return sellerSubmissionProducts.isEmpty ? "Add Your First Drop Item" : "Edit Your Drop Lineup"
        }
        return "Prep Your Next Drop"
    }

    private var sellerActionSubtitle: String {
        if submissionWindowOpen {
            return sellerSubmissionProducts.isEmpty
                ? "Add premium products over $10 for this Friday-Sunday feature."
                : "Update this week's premium products, pricing, and open slots."
        }
        return "Review your lineup and get ready before the next Friday opening."
    }

    private var sellerActionIcon: String {
        if submissionWindowOpen {
            return sellerSubmissionProducts.isEmpty ? "sparkles" : "shippingbox.fill"
        }
        return "calendar.badge.plus"
    }

    // MARK: - Load

    private func loadDrop() async {
        isLoading = true
        errorMessage = nil

        if sellerPreviewMode {
            dropResponse = previewDropResponse
            if isSeller {
                sellerSubmissions = .preview(sellerId: sellerId)
            }
            isLoading = false
            return
        }

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
        }

        isLoading = false
    }

    private var previewDropResponse: CurrentDropResponse {
        let products = MockData.products.prefix(4).map { product in
            DropProduct(
                id: product.id,
                sellerId: product.sellerId,
                name: product.name,
                priceCents: product.priceCents,
                category: product.category.rawValue,
                imageURLs: product.imageNames,
                demoVideoURL: product.demoVideoURL?.absoluteString,
                material: product.material,
                durabilityNote: product.durabilityNote,
                careWarnings: product.careWarnings,
                shipsInMinDays: product.shipsInDays.lowerBound,
                shipsInMaxDays: product.shipsInDays.upperBound,
                submittedAt: "2026-03-08T12:00:00Z"
            )
        }

        return CurrentDropResponse(
            active: true,
            weekId: "preview-week",
            startsAt: "2026-03-06T00:00:00Z",
            endsAt: "2026-03-09T00:00:00Z",
            products: products,
            nextDropAt: nil
        )
    }
}

// MARK: - Drop Product Row (uses DropProduct instead of Product)

private struct DropProductRow: View {
    let product: DropProduct

    var body: some View {
        HStack(spacing: TBTheme.spacingSM) {
            StorefrontImageView(reference: product.primaryImageReference) {
                RoundedRectangle(cornerRadius: TBTheme.radiusMD)
                    .fill(TBTheme.heroGradient)
                    .overlay {
                        Image(systemName: "cube.fill")
                            .font(.title2)
                            .foregroundStyle(TBTheme.skyBlue)
                    }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: TBTheme.radiusMD, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.tbProductTitleSM)
                    .tbProductNameTitleStyle()

                Text(Money.format(cents: product.priceCents))
                    .font(.tbProductPriceSM)
                    .foregroundStyle(.primary.opacity(0.82))

                Text(product.material)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Seller")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(product.sellerId.replacingOccurrences(of: "seller_", with: "#"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TBTheme.skyBlue)
            }
        }
        .padding(.horizontal, TBTheme.spacingMD)
        .padding(.vertical, TBTheme.spacingSM)
        .background(TBTheme.cardGradient)
        .cornerRadius(TBTheme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .strokeBorder(TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(product.name), \(Money.format(cents: product.priceCents)), \(product.material), seller \(product.sellerId)")
    }
}

#Preview {
    DropView()
        .environmentObject(CartStore())
        .environmentObject(CatalogStore())
        .environmentObject(SellerSubscriptionStore.previewActive)
}
