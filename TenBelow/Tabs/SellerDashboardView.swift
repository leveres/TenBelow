//
//  SellerDashboardView.swift
//  TenBelow
//

import SwiftUI

struct SellerDashboardView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore
    @EnvironmentObject private var orderStore: OrderStore
    @EnvironmentObject private var inquiryStore: SellerInquiryStore
    @AppStorage("catalogRefreshToken") private var catalogRefreshToken = 0
    @AppStorage("sellerSellerId") private var sellerSellerId = ""
    let products: [Product]
    @State private var seller: SellerProfile
    @State private var showAddProductFlow = false
    @State private var customOrderPendingCount: Int?
    @State private var lastDashboardRefresh = Date.distantPast
    private var shippingSnapshot: SellerDashboardShippingSnapshot { .load() }
    private var policySnapshot: SellerDashboardPolicySnapshot { .load() }

    init(seller: SellerProfile, products: [Product]) {
        self.products = products
        _seller = State(initialValue: seller)
    }

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var sellerProducts: [Product] {
        let currentSellerProducts = storefrontProducts.filter { $0.sellerId == seller.id }
        return currentSellerProducts.isEmpty ? products : currentSellerProducts
    }

    private var resolvedCurrentSeller: SellerProfile {
        let resolved = resolvedSellerProfile(
            sellerId: seller.id,
            storefrontProducts: sellerProducts,
            remoteProfiles: catalog.sellerProfiles
        )
        return resolved?.mergingFallback(seller) ?? seller
    }

    private var messageThreadCount: Int {
        MessagingInbox.sellerEntries(
            orders: orderStore.orders,
            inquiryThreads: inquiryStore.sellerThreads,
            sellerId: seller.id
        ).count
    }

    private var storedSellerProfile: SellerProfile? {
        SellerProfile.locallyStoredProfile().flatMap { profile in
            profile.id == seller.id ? profile : nil
        }
    }

    private var sellerProfileFingerprint: String {
        [
            resolvedCurrentSeller.displayName,
            resolvedCurrentSeller.handle,
            resolvedCurrentSeller.location,
            resolvedCurrentSeller.processingTime,
            resolvedCurrentSeller.materials.joined(separator: ","),
            "\(resolvedCurrentSeller.shipsInDays.lowerBound)",
            "\(resolvedCurrentSeller.shipsInDays.upperBound)",
            resolvedCurrentSeller.avatarURL?.absoluteString ?? "",
            resolvedCurrentSeller.bannerURL?.absoluteString ?? "",
            resolvedCurrentSeller.websiteURL?.absoluteString ?? "",
            "\(resolvedCurrentSeller.productCount)",
            "\(resolvedCurrentSeller.pageViewCount)",
            "\(resolvedCurrentSeller.likeCount)"
        ].joined(separator: "|")
    }

    private var dashboardAvatarReference: String? {
        cacheBustedMediaReference(for: resolvedCurrentSeller.avatarURL)
    }

    private var dashboardBannerReference: String? {
        cacheBustedMediaReference(for: resolvedCurrentSeller.bannerURL)
    }

    var body: some View {
        VStack(spacing: 12) {
            headerCard
            primaryActions
            secondaryActions
            settingsSection
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TBTheme.spacingLG)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TBFrostBackground())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showAddProductFlow) {
            SellerProductsView(
                seller: seller,
                products: sellerProducts,
                startInAddMode: true
            )
        }
        .task {
            #if DEBUG
            print("[SellerDashboard] task start sellerId=\(seller.id)")
            #endif
            await SellerStoreSettingsSync.refreshLocalCache(sellerId: seller.id)
            refreshSellerFromLatestSources()
            await refreshDashboardIfNeeded()
        }
        .onChange(of: sellerProfileFingerprint) { _, _ in
            #if DEBUG
            print("[SellerDashboard] fingerprint changed sellerId=\(seller.id)")
            #endif
            refreshSellerFromLatestSources()
        }
        .onChange(of: catalogRefreshToken) { _, _ in
            #if DEBUG
            print("[SellerDashboard] catalogRefreshToken changed sellerId=\(seller.id) token=\(catalogRefreshToken)")
            #endif
            refreshSellerFromLatestSources()
            Task { await refreshDashboardIfNeeded(force: true) }
        }
    }

    private var customRequestsSubtitle: String {
        if let customOrderPendingCount, customOrderPendingCount > 0 {
            return "\(customOrderPendingCount) pending · sketches & details"
        }
        return "View and respond to buyer submissions"
    }

    private func refreshCustomOrderPendingCount() async {
        do {
            let list = try await CustomOrderAPI.fetchSellerRequests(sellerId: seller.id)
            let pending = list.filter { $0.status == .pending }.count
            await MainActor.run { customOrderPendingCount = pending }
        } catch {
            await MainActor.run { customOrderPendingCount = nil }
        }
    }

    private func refreshDashboardIfNeeded(force: Bool = false) async {
        let now = Date()
        guard force || now.timeIntervalSince(lastDashboardRefresh) > 45 else { return }
        lastDashboardRefresh = now
        await sellerSubscription.refresh()
        await refreshCustomOrderPendingCount()
        let sid = sellerSellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sid.isEmpty {
            async let orders: Void = orderStore.refreshSellerOrders(sellerId: sid)
            async let inquiries: Void = inquiryStore.refreshSellerThreads()
            _ = await (orders, inquiries)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                StorefrontImageView(reference: dashboardBannerReference, contentMode: .fill) {
                    LinearGradient(
                        colors: StorefrontBrandTheme.defaultBannerColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()

                LinearGradient(
                    colors: [
                        .clear,
                        Color.black.opacity(0.28),
                        Color.black.opacity(0.66)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 10) {
                    sellerHeroProfileRow
                    headerChips
                }
                .padding(16)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
            }
        }
        .frame(height: 188)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.08), radius: 12, y: 5)
    }

    private var sellerHeroProfileRow: some View {
        HStack(alignment: .center, spacing: 12) {
            StorefrontImageView(reference: dashboardAvatarReference, contentMode: .fill) {
                Circle()
                    .fill(.white.opacity(0.96))
                    .overlay(
                        Text(avatarInitials)
                            .font(.subheadline.weight(.bold))
                            .fontWeight(.bold)
                            .foregroundStyle(TBTheme.deepSky)
                    )
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(0.78), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 6) {
                    Text(headerDisplayName)
                        .font(.tbSectionTitle)
                        .foregroundStyle(.white.opacity(0.97))
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    if resolvedCurrentSeller.showsVerifiedBadge {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.94))
                            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    }
                }

                Text(headerHandle)
                    .font(.tbBody)
                    .foregroundStyle(.white.opacity(0.84))
                    .shadow(color: .black.opacity(0.42), radius: 2, y: 1)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            NavigationLink {
                EditSellerProfileView(seller: $seller)
            } label: {
                Text("Edit")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.90))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var headerDisplayName: String {
        let trimmed = resolvedCurrentSeller.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Your store" : trimmed
    }

    private var headerHandle: String {
        let trimmed = resolvedCurrentSeller.handle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "@tenbelow" : trimmed
    }

    private var headerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip(icon: "shippingbox", text: "Ships in \(shippingSnapshot.minShipDays)–\(shippingSnapshot.maxShipDays) days")
                chip(icon: "paperplane.fill", text: resolvedCurrentSeller.location)
            }
            .padding(.trailing, 6)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func refreshSellerFromLatestSources() {
        let latestSeller = resolvedCurrentSeller.mergingFallback(storedSellerProfile).mergingFallback(seller)
        #if DEBUG
        print(
            """
            [SellerDashboard] refresh sellerId=\(seller.id) \
            currentAvatar=\(seller.avatarURL?.absoluteString ?? "nil") \
            currentBanner=\(seller.bannerURL?.absoluteString ?? "nil") \
            storedAvatar=\(storedSellerProfile?.avatarURL?.absoluteString ?? "nil") \
            storedBanner=\(storedSellerProfile?.bannerURL?.absoluteString ?? "nil") \
            resolvedAvatar=\(resolvedCurrentSeller.avatarURL?.absoluteString ?? "nil") \
            resolvedBanner=\(resolvedCurrentSeller.bannerURL?.absoluteString ?? "nil") \
            latestAvatar=\(latestSeller.avatarURL?.absoluteString ?? "nil") \
            latestBanner=\(latestSeller.bannerURL?.absoluteString ?? "nil")
            """
        )
        #endif
        if latestSeller != seller {
            seller = latestSeller
        }
    }

    private func cacheBustedMediaReference(for url: URL?) -> String? {
        guard let url else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "tb_refresh" }
        queryItems.append(URLQueryItem(name: "tb_refresh", value: String(catalogRefreshToken)))
        components.queryItems = queryItems
        return components.url?.absoluteString ?? url.absoluteString
    }

    private var avatarInitials: String {
        let words = resolvedCurrentSeller.displayName.split(separator: " ")
        return words.prefix(2).compactMap { $0.first }.map(String.init).joined()
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.22))
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.18), lineWidth: 0.8)
        )
        .clipShape(Capsule())
        .foregroundStyle(.white.opacity(0.96))
    }

    // MARK: - Actions

    private var primaryActions: some View {
        NavigationLink {
            SellerProductsView(
                seller: seller,
                products: sellerProducts
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cube.box")
                    .font(.system(size: 16, weight: .semibold))
                Text("Manage products")
                    .font(.tbHeadline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: [TBTheme.accent, TBTheme.deepSky],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: TBTheme.accent.opacity(0.18), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var secondaryActions: some View {
        HStack(spacing: 12) {
            NavigationLink {
                SellerStoresDirectoryView(
                    currentSellerID: seller.id,
                    products: storefrontProducts
                )
            } label: {
                secondaryButton(icon: "eye", title: "View stores")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            NavigationLink {
                SellerInboxListView(seller: seller)
            } label: {
                secondaryButton(
                    icon: "bubble.left.and.bubble.right",
                    title: "Messages",
                    badgeCount: messageThreadCount
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func secondaryButton(icon: String, title: String, badgeCount: Int = 0) -> some View {
        let isHighlighted = badgeCount > 0

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.tbBodyStrong)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if isHighlighted {
                Text("\(badgeCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [TBTheme.accent, TBTheme.deepSky],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule(style: .continuous)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
                    )
            }
        }
        .foregroundStyle(isHighlighted ? TBTheme.deepSky.opacity(0.96) : TBTheme.deepSky)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
            Group {
                if isHighlighted {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            TBTheme.skyLight.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color.white.opacity(0.82)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isHighlighted ? TBTheme.skyBlue.opacity(0.16) : TBTheme.skyBlue.opacity(0.10), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: isHighlighted ? TBTheme.skyBlue.opacity(0.08) : .black.opacity(0.025), radius: 6, y: 3)
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            GlassCard(cornerRadius: 22, snowfallFlakeCount: 56) {
                VStack(spacing: 0) {
                    NavigationLink {
                        ShippingSettingsView()
                    } label: {
                        settingsRow(icon: "shippingbox", title: "Manage shipping", subtitle: shippingRowSubtitle)
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.5)

                    NavigationLink {
                        SellerPoliciesView()
                    } label: {
                        settingsRow(icon: "doc.text", title: "Manage policies", subtitle: policyRowSubtitle)
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.5)

                    NavigationLink {
                        SupportView()
                    } label: {
                        settingsRow(icon: "questionmark.circle", title: "View support", subtitle: "Help center and contact")
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.5)

                    NavigationLink {
                        SellerCustomRequestsView(seller: resolvedCurrentSeller)
                    } label: {
                        settingsRow(icon: "doc.text.image", title: "Custom requests", subtitle: customRequestsSubtitle)
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.5)

                    NavigationLink {
                        PayoutSettingsView()
                    } label: {
                        settingsRow(icon: "dollarsign.circle", title: "Manage payouts", subtitle: payoutRowSubtitle)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var shippingRowSubtitle: String {
        "\(shippingSnapshot.primaryRegion) • \(shippingSnapshot.processingTime)"
    }

    private var policyRowSubtitle: String {
        policySnapshot.dashboardSummary
    }

    private var payoutRowSubtitle: String {
        AppConstants.isStripeConfigured
            ? "Stripe Connect onboarding and payout dashboard"
            : "Connect Stripe to enable seller payouts"
    }

    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.82))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)
                Text(subtitle)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct PayoutSettingsViewDraft: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("sellerSellerId") private var sellerId = ""

    @State private var status: SellerStatusResponse?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isOpeningLink = false

    private var normalizedSellerId: String {
        sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var statusTitle: String {
        guard let status else { return "Checking payout setup" }
        if status.payoutSetupPending { return "Payout setup pending" }
        if status.onboardingComplete { return "Payouts are ready" }
        return "Finish Stripe onboarding"
    }

    private var statusMessage: String {
        guard let status else {
            return "We are checking your Stripe Connect status and seller account requirements."
        }
        if let message = status.payoutSetupMessage, !message.isEmpty {
            return message
        }
        if status.onboardingComplete {
            return "Your seller account can accept charges and receive payouts through Stripe Connect."
        }
        return "Finish Stripe Connect onboarding before selling live products and receiving payouts."
    }

    private var canOpenOnboarding: Bool {
        guard let status else { return false }
        return !status.payoutSetupPending && !status.onboardingComplete
    }

    private var canOpenDashboard: Bool {
        guard let status else { return false }
        return !status.payoutSetupPending && !status.stripeAccountId.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                payoutChecklist
                actionCard

                if let errorMessage {
                    errorCard(errorMessage)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(TBFrostBackground())
        .navigationTitle("Payouts")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadStatus()
        }
        .refreshable {
            await loadStatus()
        }
    }

    private var headerCard: some View {
        GlassCard(cornerRadius: 24, snowfallFlakeCount: 72) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(TBTheme.skyLight.opacity(0.58))
                            .frame(width: 48, height: 48)
                        Image(systemName: statusIconName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(statusIconColor)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(statusTitle)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .tracking(-0.4)
                            .foregroundStyle(TBTheme.deepSky)

                        Text(statusMessage)
                            .font(.tbBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if isLoading {
                    ProgressView("Refreshing payout status...")
                        .font(.tbCaption)
                        .tint(TBTheme.icyBlue)
                }
            }
        }
    }

    private var payoutChecklist: some View {
        GlassCard(cornerRadius: 24, snowfallFlakeCount: 48) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Setup checklist")
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)

                VStack(spacing: 10) {
                    checklistRow(
                        title: "TenBelow seller account",
                        detail: normalizedSellerId.isEmpty ? "Sign in as a seller first." : normalizedSellerId,
                        isComplete: !normalizedSellerId.isEmpty
                    )
                    checklistRow(
                        title: "Stripe Connect available",
                        detail: status?.payoutSetupPending == true ? "Waiting for TenBelow Stripe setup." : "Stripe setup is available.",
                        isComplete: status?.payoutSetupPending == false
                    )
                    checklistRow(
                        title: "Business details submitted",
                        detail: status?.detailsSubmitted == true ? "Stripe has your details." : "Complete identity and business details in Stripe.",
                        isComplete: status?.detailsSubmitted == true
                    )
                    checklistRow(
                        title: "Charges and payouts",
                        detail: status?.onboardingComplete == true ? "Ready to sell and receive payouts." : "Charges and payouts are not fully enabled yet.",
                        isComplete: status?.onboardingComplete == true
                    )
                }
            }
        }
    }

    private var actionCard: some View {
        GlassCard(cornerRadius: 24, snowfallFlakeCount: 42) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Actions")
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)

                Button {
                    Task { await openOnboarding() }
                } label: {
                    actionButtonContent(
                        title: "Continue payout setup",
                        subtitle: canOpenOnboarding ? "Open Stripe Connect onboarding" : disabledOnboardingReason,
                        systemImage: "arrow.up.forward.app"
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canOpenOnboarding || isOpeningLink)
                .opacity(canOpenOnboarding ? 1 : 0.58)

                Button {
                    Task { await openDashboard() }
                } label: {
                    actionButtonContent(
                        title: "Open Stripe dashboard",
                        subtitle: canOpenDashboard ? "Manage payouts and account details" : "Available after Stripe Connect is created",
                        systemImage: "dollarsign.circle"
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canOpenDashboard || isOpeningLink)
                .opacity(canOpenDashboard ? 1 : 0.58)
            }
        }
    }

    private var disabledOnboardingReason: String {
        if status?.payoutSetupPending == true {
            return "TenBelow still needs Stripe keys before sellers can connect payouts"
        }
        if status?.onboardingComplete == true {
            return "Onboarding is already complete"
        }
        return "Refresh status before opening onboarding"
    }

    private var statusIconName: String {
        guard let status else { return "hourglass" }
        if status.onboardingComplete { return "checkmark.seal.fill" }
        if status.payoutSetupPending { return "clock.badge.exclamationmark" }
        return "person.crop.circle.badge.exclamationmark"
    }

    private var statusIconColor: Color {
        guard let status else { return TBTheme.icyBlue }
        if status.onboardingComplete { return .green }
        if status.payoutSetupPending { return .orange }
        return TBTheme.icyBlue
    }

    private func checklistRow(title: String, detail: String, isComplete: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isComplete ? .green : TBTheme.deepSky.opacity(0.42))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)
                Text(detail)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButtonContent(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TBTheme.deepSky)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)
                Text(subtitle)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.55))
        }
        .padding(14)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
        )
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.tbCaption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @MainActor
    private func loadStatus() async {
        guard !normalizedSellerId.isEmpty else {
            errorMessage = "Sign in as a seller to view payout setup."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            status = try await SellerPayoutAPI.fetchStatus(sellerId: normalizedSellerId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func openOnboarding() async {
        await openPayoutURL {
            try await SellerPayoutAPI.fetchOnboardingLink(sellerId: normalizedSellerId)
        }
    }

    @MainActor
    private func openDashboard() async {
        await openPayoutURL {
            try await SellerPayoutAPI.fetchDashboardLink(sellerId: normalizedSellerId)
        }
    }

    @MainActor
    private func openPayoutURL(_ loadURL: () async throws -> URL) async {
        isOpeningLink = true
        errorMessage = nil
        defer { isOpeningLink = false }

        do {
            let url = try await loadURL()
            openURL(url)
        } catch {
            errorMessage = error.localizedDescription
            await loadStatus()
        }
    }
}

private enum SellerPayoutAPI {
    static func fetchStatus(sellerId: String) async throws -> SellerStatusResponse {
        try await get(pathComponents: ["seller-onboarding-status", sellerId])
    }

    static func fetchOnboardingLink(sellerId: String) async throws -> URL {
        let response: OnboardingLinkResponse = try await get(pathComponents: ["seller-onboarding-link", sellerId])
        guard let url = URL(string: response.onboardingUrl), !response.onboardingUrl.isEmpty else {
            throw SellerPayoutAPIError(message: "Payout onboarding is not available yet.")
        }
        return url
    }

    static func fetchDashboardLink(sellerId: String) async throws -> URL {
        let response: DashboardLinkResponse = try await get(pathComponents: ["seller-dashboard-link", sellerId])
        guard let url = URL(string: response.dashboardUrl), !response.dashboardUrl.isEmpty else {
            throw SellerPayoutAPIError(message: "Stripe dashboard is not available yet.")
        }
        return url
    }

    private static func get<T: Decodable>(pathComponents: [String]) async throws -> T {
        guard let baseURL = AppConstants.backendBaseURL else {
            throw SellerPayoutAPIError(message: "Connect the TenBelow backend before checking payouts.")
        }

        try await MarketplaceAuthSession.ensureSellerSessionReady()

        let url = pathComponents.reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        AppConstants.applyAppClientAuth(to: &request)
        MarketplaceAuthSession.applySellerAuth(to: &request)

        let (data, response) = try await URLSession.tenBelow.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let serverError = try? JSONDecoder().decode(SellerPayoutAPIErrorResponse.self, from: data) {
                throw SellerPayoutAPIError(message: serverError.error)
            }
            throw SellerPayoutAPIError(message: "Payout setup is unavailable right now.")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct SellerPayoutAPIErrorResponse: Decodable {
    let error: String
}

private struct SellerPayoutAPIError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

// MARK: - Preview

private struct SellerStoresDirectoryView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore

    @State private var currentStorePage = 0

    let currentSellerID: String
    let products: [Product]

    private let profilesPerPage = 5

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: products.isEmpty ? localProducts.products : products
        )
    }

    private var sellerProfiles: [SellerProfile] {
        var profilesByID: [String: SellerProfile] = [:]

        for profile in catalog.sellerProfiles {
            profilesByID[profile.id] = profile.applyingStorefrontProducts(
                storefrontProducts.filter { $0.sellerId == profile.id }
            )
        }

        for (sellerId, profile) in resolvedSellerProfilesByID(
            storefrontProducts: storefrontProducts,
            remoteProfiles: catalog.sellerProfiles
        ) {
            profilesByID[sellerId] = profile.mergingFallback(profilesByID[sellerId])
        }

        return profilesByID.values.sorted { lhs, rhs in
            if lhs.id == currentSellerID { return true }
            if rhs.id == currentSellerID { return false }
            if lhs.productCount == rhs.productCount {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.productCount > rhs.productCount
        }
    }

    private var totalStorePages: Int {
        max(1, Int(ceil(Double(sellerProfiles.count) / Double(profilesPerPage))))
    }

    private var visibleSellerProfiles: [SellerProfile] {
        let safePage = min(max(currentStorePage, 0), totalStorePages - 1)
        let startIndex = safePage * profilesPerPage
        let endIndex = min(startIndex + profilesPerPage, sellerProfiles.count)
        guard startIndex < endIndex else { return [] }
        return Array(sellerProfiles[startIndex..<endIndex])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
            directoryHeader
                .padding(.horizontal, 20)

            if sellerProfiles.isEmpty {
                emptyState
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 14) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 0)
                        ],
                        alignment: .center,
                        spacing: 12
                    ) {
                        ForEach(visibleSellerProfiles) { profile in
                            NavigationLink {
                                PublicSellerProfileView(
                                    seller: profile,
                                    products: storefrontProducts.filter { $0.sellerId == profile.id }
                                )
                            } label: {
                                sellerStoreTile(profile)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)

                    if totalStorePages > 1 {
                        storePaginationControls
                            .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TBFrostBackground())
        .navigationTitle("")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                EmptyView()
            }
        }
        .task {
            await catalog.load()
        }
        .onChange(of: sellerProfiles.count) { _, _ in
            currentStorePage = min(currentStorePage, totalStorePages - 1)
        }
    }

    private var directoryHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            SnowfallTitleContainer(cornerRadius: 30, horizontalPadding: 8, verticalPadding: 4, flakeCount: 82) {
                Image("StoresTitle")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 248, height: 82, alignment: .center)
                    .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, -6)
            .padding(.leading, -8)

            Text("Browse other TenBelow makers, study their storefronts, and see how sellers are presenting their products.")
                .font(.tbBody)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var storePaginationControls: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalStorePages, id: \.self) { page in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        currentStorePage = page
                    }
                } label: {
                    Text("\(page + 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(page == currentStorePage ? .white : TBTheme.deepSky)
                        .frame(width: 28, height: 28)
                        .background(
                            Capsule(style: .continuous)
                                .fill(page == currentStorePage ? TBTheme.accent : Color.white.opacity(0.86))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(TBTheme.skyBlue.opacity(0.22), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func sellerStoreTile(_ profile: SellerProfile) -> some View {
        HStack(alignment: .center, spacing: 12) {
            StorefrontImageView(reference: profile.avatarURL?.absoluteString, contentMode: .fill) {
                Circle()
                    .fill(TBTheme.skyLight.opacity(0.58))
                    .overlay {
                        Text(avatarInitials(for: profile))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(TBTheme.deepSky)
                    }
            }
            .frame(width: 46, height: 46)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(storeStatusText(for: profile))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.icyBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(storeMetricText(for: profile))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.icyBlue.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(profile.handle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            viewStoreCapsule
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 340, minHeight: 94, alignment: .center)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    TBTheme.skyLight.opacity(0.26)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.16), lineWidth: 0.8)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.035), radius: 8, y: 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sellerStoreRow(_ profile: SellerProfile) -> some View {
        HStack(alignment: .center, spacing: 12) {
            StorefrontImageView(reference: profile.avatarURL?.absoluteString, contentMode: .fill) {
                Circle()
                    .fill(TBTheme.skyLight.opacity(0.52))
                    .overlay {
                        Text(avatarInitials(for: profile))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(TBTheme.deepSky)
                    }
            }
            .frame(width: 54, height: 54)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(0.82), lineWidth: 2)
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(profile.displayName)
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)
                        .lineLimit(1)

                    if profile.showsVerifiedBadge {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TBTheme.icyBlue)
                    }

                    if profile.id == currentSellerID {
                        Text("You")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(TBTheme.accent, in: Capsule())
                    }
                }

                Text(profile.handle)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    sellerDirectoryPill(icon: "cube.box", text: "\(profile.productCount) product\(profile.productCount == 1 ? "" : "s")")
                    if profile.rating > 0 {
                        sellerDirectoryPill(icon: "star.fill", text: String(format: "%.1f", profile.rating))
                    }
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(TBTheme.deepSky.opacity(0.46))
        }
        .padding(14)
        .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
        )
    }

    private func sellerDirectoryPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(
            LinearGradient(
                colors: [TBTheme.deepSky, TBTheme.icyBlue],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.94),
                            TBTheme.skyLight.opacity(0.62)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.3), lineWidth: 0.75)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.06), radius: 2, y: 1)
    }

    private var viewStoreCapsule: some View {
        HStack(spacing: 4) {
            Text("View")
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(TBTheme.deepSky)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.94),
                            TBTheme.skyLight.opacity(0.52)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.3), lineWidth: 0.75)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.06), radius: 2, y: 1)
    }

    private func storeStatusText(for profile: SellerProfile) -> String {
        if profile.id == currentSellerID {
            return "Your store"
        }
        if profile.showsVerifiedBadge {
            return "Verified seller"
        }
        return "Seller store"
    }

    private func storeMetricText(for profile: SellerProfile) -> String {
        let productText = "\(profile.productCount) product\(profile.productCount == 1 ? "" : "s")"
        guard profile.rating > 0 else { return productText }
        return "\(productText) • \(String(format: "%.1f", profile.rating))"
    }

    private var emptyState: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Label("No seller stores yet", systemImage: "storefront")
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)

                Text("Seller profiles will appear here once shops are published in the catalog.")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func avatarInitials(for profile: SellerProfile) -> String {
        let initials = profile.displayName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
        return initials.isEmpty ? "TB" : initials
    }
}


private enum SellerDashboardSettingsStorageKey {
    static let shipping = "sellerShippingSettingsData"
    static let policies = "sellerPolicySettingsData"
}

private struct SellerDashboardShippingSnapshot: Codable {
    let processingTime: String
    let minShipDays: Int
    let maxShipDays: Int
    let primaryRegion: String

    static func load() -> SellerDashboardShippingSnapshot {
        if let data = UserDefaults.standard.data(forKey: SellerDashboardSettingsStorageKey.shipping),
           let saved = try? JSONDecoder().decode(SellerDashboardShippingSnapshot.self, from: data) {
            return saved
        }

        return SellerDashboardShippingSnapshot(
            processingTime: "1-2 business days",
            minShipDays: 2,
            maxShipDays: 4,
            primaryRegion: "United States"
        )
    }
}

private struct SellerDashboardPolicySnapshot: Codable {
    let acceptsReturns: Bool
    let returnWindowDays: Int
    let allowsExchanges: Bool
    let allowsCancellations: Bool
    let cancellationWindowHours: Int

    static func load() -> SellerDashboardPolicySnapshot {
        if let data = UserDefaults.standard.data(forKey: SellerDashboardSettingsStorageKey.policies),
           let saved = try? JSONDecoder().decode(SellerDashboardPolicySnapshot.self, from: data) {
            return saved
        }

        return SellerDashboardPolicySnapshot(
            acceptsReturns: true,
            returnWindowDays: 14,
            allowsExchanges: true,
            allowsCancellations: true,
            cancellationWindowHours: 12
        )
    }

    var dashboardSummary: String {
        let returnsText = acceptsReturns ? "\(returnWindowDays)-day returns" : "No returns"
        let exchangesText = allowsExchanges ? "exchanges on" : "no exchanges"
        let cancellationText = allowsCancellations ? "\(cancellationWindowHours)h cancellations" : "no cancellations"
        return "\(returnsText) • \(exchangesText) • \(cancellationText)"
    }
}

