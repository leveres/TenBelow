import SwiftUI

struct BuyerProfileView: View {
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore
    @EnvironmentObject private var orderStore: OrderStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore

    @AppStorage("userRole") private var userRole = ""
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("buyerCheckoutPreference") private var buyerCheckoutPreference = "guest"
    @AppStorage("buyerFullName") private var buyerFullName = ""
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @AppStorage("buyerAccountCreated") private var buyerAccountCreated = false

    private var isAccountHolder: Bool {
        buyerAccountCreated && !buyerFullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var trimmedBuyerName: String {
        buyerFullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var firstName: String {
        trimmedBuyerName.split(separator: " ").first.map(String.init) ?? "Buyer"
    }

    private var avatarInitials: String {
        let parts = trimmedBuyerName.split(whereSeparator: \.isWhitespace)
        let letters = parts.prefix(2).compactMap { $0.first.map { String($0).uppercased() } }
        if !letters.isEmpty {
            return letters.joined()
        }
        return "TB"
    }

    private var accountTitle: String {
        isAccountHolder ? firstName : "Guest Account"
    }

    private var accountSubtitle: String {
        isAccountHolder
            ? "Your private space for favorites and orders — nothing here is a public storefront or profile."
            : "Browse freely now, then create an account when you want saved details and a faster repeat checkout."
    }

    private var checkoutModeTitle: String {
        isAccountHolder ? "Account checkout enabled" : "Guest checkout active"
    }

    private var checkoutModeDescription: String {
        isAccountHolder
            ? "Purchases stay attached to \(buyerEmail.isEmpty ? "your TenBelow buyer account" : buyerEmail)."
            : "Your order history stays private, but checkout details are not saved for next time."
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                accountHeroCard
                    .padding(.top, 12)

                if isAccountHolder {
                    registeredBuyerHubCard
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(
                            title: "Quick actions",
                            subtitle: "The buyer view is private to you. Nothing here creates a public storefront."
                        )

                        NavigationLink {
                            OrdersView()
                        } label: {
                            accountRow(
                                icon: "bag",
                                title: "My Orders",
                                subtitle: "Track purchases, delivery updates, and any production previews."
                            )
                        }
                        .buttonStyle(.plain)

                        if isAccountHolder {
                            accountRow(
                                icon: "envelope.badge",
                                title: "Saved email",
                                subtitle: buyerEmail.isEmpty ? "Email will be added during checkout." : buyerEmail
                            )
                        } else {
                            Button {
                                restartBuyerSetup()
                            } label: {
                                accountRow(
                                    icon: "person.crop.circle.badge.plus",
                                    title: "Create buyer account",
                                    subtitle: "Go back through the quick buyer setup and save your details."
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if isAccountHolder {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionHeader(
                                title: "Need anything?",
                                subtitle: "Support is still available even though buyer accounts stay private."
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Support")
                                    .font(.tbBodyStrong)
                                    .foregroundStyle(TBTheme.deepSky)
                                Text("support@tenbelow.com")
                                    .font(.tbBody)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                signOutBuyer()
                            } label: {
                                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                            .buttonStyle(SecondaryCTAButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(TBTheme.cloudWhite.ignoresSafeArea())
        .navigationTitle("Account")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Registered buyer hub (private — not a public page)

    private var favoriteProductsForHub: [Product] {
        let ids = buyerEngagement.favoriteProductIDs
        return ids.compactMap { localProducts.product(withId: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var recentOrdersForAccount: [Order] {
        let email = buyerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { return [] }
        return orderStore.orders
            .filter {
                $0.buyerEmail?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == email
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var recentOrdersPreview: [Order] {
        Array(recentOrdersForAccount.prefix(3))
    }

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var followedSellersForHub: [SellerProfile] {
        buyerEngagement.followedSellerIDs
            .map { sellerProfile(for: $0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func sellerProfile(for sellerId: String) -> SellerProfile {
        if let resolvedProfile = resolvedSellerProfile(
            sellerId: sellerId,
            storefrontProducts: storefrontProducts,
            remoteProfiles: catalog.sellerProfiles
        ) {
            return resolvedProfile
        }

        let fallbackName = sellerId.replacingOccurrences(of: "_", with: " ").capitalized
        return SellerProfile.previewProfile(
            sellerId: sellerId,
            businessName: fallbackName.isEmpty ? "Seller" : fallbackName
        )
    }

    private func products(for seller: SellerProfile) -> [Product] {
        storefrontProducts.filter { $0.sellerId == seller.id }
    }

    private var registeredBuyerHubCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Your TenBelow",
                    subtitle: "Favorites and purchases tied to your account. Only you see this — it is not shared like a seller storefront."
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Favorites")
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)

                    if favoriteProductsForHub.isEmpty {
                        Text("Tap the heart on products you like while shopping. They appear here for quick access.")
                            .font(.tbBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(favoriteProductsForHub) { product in
                                    NavigationLink {
                                        ProductDetailView(product: product)
                                    } label: {
                                        BuyerHubFavoriteTile(product: product)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Divider().opacity(0.35)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Following sellers")
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)

                    if followedSellersForHub.isEmpty {
                        Text("Follow sellers from their store page to save them here.")
                            .font(.tbBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(followedSellersForHub) { seller in
                                BuyerHubFollowedSellerRow(
                                    seller: seller,
                                    onUnfollow: {
                                        _ = buyerEngagement.toggleFollow(sellerId: seller.id)
                                    }
                                ) {
                                    PublicSellerProfileView(
                                        seller: seller,
                                        products: products(for: seller)
                                    )
                                }
                            }
                        }
                    }
                }

                Divider().opacity(0.35)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Most recent buys")
                            .font(.tbBodyStrong)
                            .foregroundStyle(TBTheme.deepSky)
                        Spacer()
                        if recentOrdersForAccount.count > 3 {
                            NavigationLink("View all") {
                                OrdersView()
                            }
                            .font(.tbCaption)
                            .foregroundStyle(TBTheme.icyBlue)
                        }
                    }

                    if recentOrdersPreview.isEmpty {
                        Text("After checkout with your saved email, your orders appear here.")
                            .font(.tbBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(recentOrdersPreview) { order in
                                NavigationLink {
                                    OrderDetailView(orderId: order.id, mode: .buyer, currentSellerId: nil)
                                } label: {
                                    BuyerHubOrderRow(order: order)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var accountHeroCard: some View {
        GlassCard(cornerRadius: 26) {
            VStack(spacing: 16) {
                ZStack {
                    if isAccountHolder {
                        Text(avatarInitials)
                            .font(.system(size: 52, weight: .heavy, design: .rounded))
                            .foregroundStyle(TBTheme.deepSky)
                    } else {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(TBTheme.deepSky)
                    }
                }
                .frame(height: 64)

                VStack(spacing: 8) {
                    Text(accountTitle)
                        .font(.tbProductTitleXL)
                        .foregroundStyle(TBTheme.deepSky)

                    Text(accountSubtitle)
                        .font(.tbBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                HStack(spacing: 10) {
                    capsuleTag(
                        title: isAccountHolder ? "Account holder" : "Guest",
                        systemImage: isAccountHolder ? "person.badge.shield.checkmark" : "bag"
                    )

                    capsuleTag(
                        title: "Buyer only",
                        systemImage: "cart"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)

                if isAccountHolder {
                    VStack(spacing: 12) {
                        if !buyerEmail.isEmpty {
                            Text(buyerEmail)
                                .font(.tbBodyStrong)
                                .foregroundStyle(TBTheme.bannerCTAForeground)
                        }

                        Text("Your buyer account keeps favorites and orders in one private place.")
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                } else {
                    Button {
                        restartBuyerSetup()
                    } label: {
                        Label("Create buyer account", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.tbSectionTitle)
                .foregroundStyle(TBTheme.deepSky)

            Text(subtitle)
                .font(.tbBody)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TBTheme.deepSky)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.tbBodyStrong)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.tbBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.54))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.72), lineWidth: 1)
        )
    }

    private func capsuleTag(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.tbMicro)
            .foregroundStyle(TBTheme.deepSky)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.62), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.82), lineWidth: 1)
            )
    }

    private func restartBuyerSetup() {
        buyerAccountCreated = false
        buyerCheckoutPreference = "guest"
        userRole = ""
        hasSeenOnboarding = false
    }

    private func signOutBuyer() {
        buyerAccountCreated = false
        buyerFullName = ""
        buyerEmail = ""
        buyerCheckoutPreference = "guest"
        userRole = ""
        hasSeenOnboarding = false
    }
}

// MARK: - Hub tiles (registered buyer only)

private struct BuyerHubFavoriteTile: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StorefrontImageView(reference: product.primaryImageReference) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TBTheme.skyLight.opacity(0.30))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                )

            Text(product.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 100, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(Money.format(cents: product.priceCents))
                .font(.tbMicro)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(product.name), \(Money.format(cents: product.priceCents)), \(product.category.rawValue)")
        .accessibilityHint("Favorited product.")
    }
}

private struct BuyerHubOrderRow: View {
    let order: Order

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(order.id)
                    .font(.tbBodyStrong)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(order.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            OrderStatusPill(status: order.status)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.54))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.72), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(order.id), \(order.status.rawValue), \(order.createdAt.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityHint("Opens order details.")
    }
}

private struct BuyerHubFollowedSellerRow<Destination: View>: View {
    let seller: SellerProfile
    let onUnfollow: () -> Void
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                destination()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [TBTheme.skyLight, TBTheme.skyBlue.opacity(0.35)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 34, height: 34)

                        Text(initials)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(TBTheme.deepSky)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(seller.displayName)
                            .font(.tbBodyStrong)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(seller.handle)
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View seller \(seller.displayName)")
            .accessibilityHint(seller.handle)

            Button("Following") {
                onUnfollow()
            }
            .font(.tbCaption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(TBTheme.icyBlue)
            .controlSize(.small)
            .accessibilityLabel("Following \(seller.displayName)")
            .accessibilityHint("Double tap to unfollow.")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.54))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.72), lineWidth: 1)
        )
    }

    private var initials: String {
        let words = seller.displayName.split(separator: " ")
        let chars = words.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        return chars.isEmpty ? "TB" : chars.joined()
    }
}

#Preview {
    let events = CommerceEventStore()
    let engagement = BuyerEngagementStore(eventStore: events)
    let products = LocalProductStore(eventStore: events)
    let orders = OrderStore(eventStore: events)
    return NavigationStack {
        BuyerProfileView()
            .environmentObject(engagement)
            .environmentObject(orders)
            .environmentObject(products)
    }
    .environmentObject(CartStore())
    .environmentObject(CatalogStore())
}
