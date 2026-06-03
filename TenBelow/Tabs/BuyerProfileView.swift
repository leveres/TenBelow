import SwiftUI

struct BuyerProfileView: View {
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore
    @EnvironmentObject private var orderStore: OrderStore
    @EnvironmentObject private var inquiryStore: SellerInquiryStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @AppStorage("pendingLaunchTab") private var pendingLaunchTab = 0
    @AppStorage("buyerCheckoutPreference") private var buyerCheckoutPreference = "guest"
    @AppStorage("buyerFullName") private var buyerFullName = ""
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @AppStorage("buyerAccountCreated") private var buyerAccountCreated = false

    @State private var showBuyerAccountSetup = false
    @State private var showBuyerSignIn = false

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
            : "Browse freely now, then create an account or sign in when you want saved details and a faster repeat checkout."
    }

    private var checkoutModeTitle: String {
        isAccountHolder ? "Account checkout enabled" : "Guest checkout active"
    }

    private var checkoutModeDescription: String {
        isAccountHolder
            ? "Purchases stay attached to \(buyerEmail.isEmpty ? "your TenBelow buyer account" : buyerEmail)."
            : "Your order history stays private, but checkout details are not saved for next time."
    }

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var followedSellerProfiles: [SellerProfile] {
        buyerEngagement.followedSellerIDs
            .compactMap { sellerProfile(for: $0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var followedSellerCountDescription: String {
        let count = followedSellerProfiles.count
        if count == 0 {
            return "See the shops you follow in one place."
        }
        return "\(count) seller\(count == 1 ? "" : "s") you follow."
    }

    private var messageThreadCount: Int {
        MessagingInbox.buyerEntries(
            orders: orderStore.orders,
            inquiryThreads: inquiryStore.buyerThreads,
            sellerProfiles: catalog.sellerProfiles,
            storefrontProducts: storefrontProducts
        ).count
    }

    private var messageThreadCountDescription: String {
        let count = messageThreadCount
        if count == 0 {
            return "Shop chats and order threads with sellers."
        }
        return "\(count) conversation\(count == 1 ? "" : "s")."
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                accountHeroCard
                    .padding(.top, 12)

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(
                            title: "Quick actions",
                            subtitle: ""
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
                            NavigationLink {
                                BuyerFollowedSellersListView()
                            } label: {
                                accountRow(
                                    icon: "person.2",
                                    title: "Following",
                                    subtitle: followedSellerCountDescription
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                BuyerMessagesListView()
                            } label: {
                                accountRow(
                                    icon: "bubble.left.and.bubble.right",
                                    title: "Messages",
                                    subtitle: messageThreadCountDescription
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                BuyerAccountSecurityView()
                            } label: {
                                accountRow(
                                    icon: "envelope.badge",
                                    title: "Saved email",
                                    subtitle: buyerEmail.isEmpty
                                        ? "Email will be added during checkout."
                                        : "\(buyerEmail) • Tap to update email or password."
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
        .sheet(isPresented: $showBuyerAccountSetup) {
            NavigationStack {
                BuyerAccountSetupView()
            }
        }
        .sheet(isPresented: $showBuyerSignIn) {
            NavigationStack {
                BuyerSignInView()
            }
        }
        .task(id: buyerEmail) {
            guard buyerAccountCreated else { return }
            async let orders: Void = orderStore.refreshBuyerOrders(email: buyerEmail)
            async let inquiries: Void = inquiryStore.refreshBuyerThreads()
            _ = await (orders, inquiries)
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
                        guestAccountBadge
                    }
                }
                .frame(minHeight: 100)

                VStack(spacing: 8) {
                    Text(accountTitle)
                        .font(.tbProductTitleXL)
                        .foregroundStyle(TBTheme.deepSky)
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
                    }
                } else {
                    VStack(spacing: 10) {
                        Button {
                            showBuyerAccountSetup = true
                        } label: {
                            Label("Create buyer account", systemImage: "person.crop.circle.badge.plus")
                        }
                        .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))

                        Button {
                            showBuyerSignIn = true
                        } label: {
                            Label("Sign in to existing account", systemImage: "arrow.right.circle")
                        }
                        .buttonStyle(SecondaryCTAButtonStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var guestAccountBadge: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            // Match home header: bound height only so the wide mark keeps its aspect ratio and stays fully visible.
            .frame(height: 96)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Guest TenBelow account")
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.tbSectionTitle)
                .foregroundStyle(TBTheme.deepSky)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.tbBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private func sellerProfile(for sellerId: String) -> SellerProfile? {
        resolvedSellerProfile(
            sellerId: sellerId,
            storefrontProducts: storefrontProducts.filter { $0.sellerId == sellerId },
            remoteProfiles: catalog.sellerProfiles
        )
    }

    private func signOutBuyer() {
        MarketplaceAuthSession.clearBuyerSession()
        buyerAccountCreated = false
        buyerFullName = ""
        buyerEmail = ""
        buyerCheckoutPreference = "guest"
        pendingLaunchTab = 0
    }
}

