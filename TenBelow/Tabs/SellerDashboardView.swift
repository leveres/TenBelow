//
//  SellerDashboardView.swift
//  TenBelow
//

import SwiftUI

struct SellerDashboardView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore
    @EnvironmentObject private var buyerSellerThreads: BuyerSellerThreadStore
    @AppStorage("catalogRefreshToken") private var catalogRefreshToken = 0
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
        buyerSellerThreads.threadsForSellerOrderedByRecentMessage(sellerId: seller.id).count
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
        .background(TBTheme.cloudWhite.ignoresSafeArea())
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
    }

    // MARK: - Header

    private var headerCard: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                StorefrontImageView(reference: dashboardBannerReference, contentMode: .fill) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.58, blue: 0.96),
                            Color(red: 0.48, green: 0.72, blue: 0.98),
                            Color(red: 0.83, green: 0.91, blue: 1.0)
                        ],
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

// MARK: - Preview

private struct SellerStoresDirectoryView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore

    let currentSellerID: String
    let products: [Product]

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

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                directoryHeader

                if sellerProfiles.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 138, maximum: 172), spacing: 18),
                            GridItem(.flexible(minimum: 138, maximum: 172), spacing: 18)
                        ],
                        alignment: .center,
                        spacing: 16
                    ) {
                        ForEach(sellerProfiles) { profile in
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
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 0)
            .padding(.bottom, TBTheme.spacingXL)
        }
        .background(TBTheme.cloudWhite.ignoresSafeArea())
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
        .refreshable {
            await catalog.load()
        }
    }

    private var directoryHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            SnowfallTitleContainer(cornerRadius: 30, horizontalPadding: 8, verticalPadding: 4, flakeCount: 82) {
                Image("StoresTitle")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 328, height: 118, alignment: .center)
                    .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, -6)

            Text("Browse other TenBelow makers, study their storefronts, and see how sellers are presenting their products.")
                .font(.tbBody)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sellerStoreTile(_ profile: SellerProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                StorefrontImageView(reference: profile.avatarURL?.absoluteString, contentMode: .fill) {
                    Circle()
                        .fill(TBTheme.skyLight.opacity(0.58))
                        .overlay {
                            Text(avatarInitials(for: profile))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(TBTheme.deepSky)
                        }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)

                    Text(storeStatusText(for: profile))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.icyBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(storeMetricText(for: profile))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.icyBlue.opacity(0.86))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text(profile.handle)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 4)

                viewStoreCapsule
            }
        }
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    TBTheme.skyLight.opacity(0.62),
                    Color.white.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.25), lineWidth: 0.9)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.045), radius: 8, y: 3)
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
                .font(.system(size: 8, weight: .bold, design: .rounded))
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(TBTheme.deepSky)
        .lineLimit(1)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
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

