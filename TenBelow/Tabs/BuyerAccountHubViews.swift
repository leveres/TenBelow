import SwiftUI

struct BuyerFollowedSellersListView: View {
    @EnvironmentObject private var buyerEngagement: BuyerEngagementStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var followedSellers: [SellerProfile] {
        buyerEngagement.followedSellerIDs
            .compactMap { sellerProfile(for: $0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        Group {
            if followedSellers.isEmpty {
                buyerAccountEmptyState(
                    title: "No followed sellers yet",
                    subtitle: "Follow sellers from their storefront to keep them easy to find here.",
                    systemImage: "person.2"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(followedSellers) { seller in
                            NavigationLink {
                                PublicSellerProfileView(
                                    seller: seller,
                                    products: products(for: seller)
                                )
                            } label: {
                                buyerAccountListRow(
                                    icon: "person.crop.circle",
                                    title: seller.displayName,
                                    subtitle: seller.handle,
                                    seller: seller
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TBTheme.cloudWhite.ignoresSafeArea())
        .navigationTitle("Following")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func sellerProfile(for sellerId: String) -> SellerProfile? {
        resolvedSellerProfile(
            sellerId: sellerId,
            storefrontProducts: storefrontProducts.filter { $0.sellerId == sellerId },
            remoteProfiles: catalog.sellerProfiles
        )
    }

    private func products(for seller: SellerProfile) -> [Product] {
        storefrontProducts.filter { $0.sellerId == seller.id }
    }
}

struct BuyerMessagesListView: View {
    @EnvironmentObject private var orderStore: OrderStore
    @EnvironmentObject private var inquiryStore: SellerInquiryStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @AppStorage("buyerEmail") private var buyerEmail = ""
    @AppStorage("buyerAccountCreated") private var buyerAccountCreated = false

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var inboxEntries: [MessagingInboxEntry] {
        MessagingInbox.buyerEntries(
            orders: orderStore.orders,
            inquiryThreads: inquiryStore.buyerThreads,
            sellerProfiles: catalog.sellerProfiles,
            storefrontProducts: storefrontProducts
        )
    }

    var body: some View {
        Group {
            if inboxEntries.isEmpty {
                buyerAccountEmptyState(
                    title: "No messages yet",
                    subtitle: "Message a seller from their shop, or open a thread from order details after checkout.",
                    systemImage: "bubble.left.and.bubble.right"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(inboxEntries) { entry in
                            NavigationLink {
                                messagingThreadView(for: entry)
                            } label: {
                                MessagingInboxRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TBTheme.cloudWhite.ignoresSafeArea())
        .navigationTitle("Messages")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: buyerEmail) {
            guard buyerAccountCreated else { return }
            async let orders: Void = orderStore.refreshBuyerOrders(email: buyerEmail)
            async let inquiries: Void = inquiryStore.refreshBuyerThreads()
            _ = await (orders, inquiries)
        }
        .refreshable {
            guard buyerAccountCreated else { return }
            async let orders: Void = orderStore.refreshBuyerOrders(email: buyerEmail)
            async let inquiries: Void = inquiryStore.refreshBuyerThreads()
            _ = await (orders, inquiries)
        }
    }

    @ViewBuilder
    private func messagingThreadView(for entry: MessagingInboxEntry) -> some View {
        switch entry.kind {
        case .shopInquiry:
            OrderSupportThreadView(
                sellerId: entry.sellerId,
                sellerName: entry.sellerName,
                viewerRole: .buyer
            )
            .environmentObject(orderStore)
            .environmentObject(inquiryStore)
        case .order(let orderId, _):
            OrderSupportThreadView(
                orderId: orderId,
                sellerId: entry.sellerId,
                sellerName: entry.sellerName,
                viewerRole: .buyer
            )
            .environmentObject(orderStore)
            .environmentObject(inquiryStore)
        }
    }
}

struct SellerInboxListView: View {
    let seller: SellerProfile

    @EnvironmentObject private var orderStore: OrderStore
    @EnvironmentObject private var inquiryStore: SellerInquiryStore
    @AppStorage("sellerSellerId") private var sellerSellerId = ""

    private var inboxEntries: [MessagingInboxEntry] {
        MessagingInbox.sellerEntries(
            orders: orderStore.orders,
            inquiryThreads: inquiryStore.sellerThreads,
            sellerId: seller.id
        )
    }

    var body: some View {
        Group {
            if inboxEntries.isEmpty {
                buyerAccountEmptyState(
                    title: "No buyer messages yet",
                    subtitle: "Shop questions and order threads from buyers appear here.",
                    systemImage: "bubble.left.and.bubble.right"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(inboxEntries) { entry in
                            NavigationLink {
                                sellerMessagingThreadView(for: entry)
                            } label: {
                                MessagingInboxRow(entry: entry, isSellerInbox: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TBTheme.cloudWhite.ignoresSafeArea())
        .navigationTitle("Messages")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: seller.id) {
            let sid = sellerSellerId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sid.isEmpty else { return }
            async let orders: Void = orderStore.refreshSellerOrders(sellerId: sid)
            async let inquiries: Void = inquiryStore.refreshSellerThreads()
            _ = await (orders, inquiries)
        }
        .refreshable {
            let sid = sellerSellerId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sid.isEmpty else { return }
            async let orders: Void = orderStore.refreshSellerOrders(sellerId: sid)
            async let inquiries: Void = inquiryStore.refreshSellerThreads()
            _ = await (orders, inquiries)
        }
    }

    @ViewBuilder
    private func sellerMessagingThreadView(for entry: MessagingInboxEntry) -> some View {
        switch entry.kind {
        case .shopInquiry:
            OrderSupportThreadView(
                sellerId: entry.sellerId,
                sellerName: seller.displayName,
                viewerRole: .seller,
                inquiryBuyerEmail: entry.inquiryBuyerEmail
            )
            .environmentObject(orderStore)
            .environmentObject(inquiryStore)
        case .order(let orderId, _):
            OrderSupportThreadView(
                orderId: orderId,
                sellerId: entry.sellerId,
                sellerName: entry.sellerName,
                viewerRole: .seller
            )
            .environmentObject(orderStore)
            .environmentObject(inquiryStore)
        }
    }
}

struct MessagingInboxRow: View {
    let entry: MessagingInboxEntry
    var isSellerInbox: Bool = false

    private var title: String {
        isSellerInbox ? entry.buyerLabel : entry.sellerName
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.isShopInquiry ? "storefront.fill" : "bubble.left.and.bubble.right.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TBTheme.deepSky)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.tbBodyStrong)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if !entry.lastMessageTimestamp.isEmpty {
                        Text(entry.lastMessageTimestamp)
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(entry.contextLabel)
                    .font(.tbCaption)
                    .foregroundStyle(TBTheme.icyBlue)
                    .lineLimit(1)

                Text(entry.lastMessageText)
                    .font(.tbBody)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
}

private func buyerAccountListRow(icon: String, title: String, subtitle: String, seller: SellerProfile? = nil) -> some View {
    HStack(alignment: .top, spacing: 12) {
        buyerAccountRowIcon(icon, seller: seller)

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

@ViewBuilder
private func buyerAccountRowIcon(_ icon: String, seller: SellerProfile? = nil) -> some View {
    if icon == "person.crop.circle", let seller {
        StorefrontImageView(reference: seller.avatarURL?.absoluteString, contentMode: .fill) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white, Color(red: 0.90, green: 0.95, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Text(sellerAvatarInitials(for: seller))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.24, green: 0.47, blue: 0.78))
                }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.05), lineWidth: 0.8)
        )
    } else {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(TBTheme.deepSky)
            .frame(width: 24, height: 24)
    }
}

private func sellerAvatarInitials(for seller: SellerProfile) -> String {
    let words = seller.displayName.split(whereSeparator: \.isWhitespace)
    let initials = words.prefix(2).compactMap { $0.first }.map(String.init)
    if !initials.isEmpty {
        return initials.joined().uppercased()
    }
    let fallback = seller.handle.replacingOccurrences(of: "@", with: "")
    return String(fallback.prefix(2)).uppercased()
}

private func buyerAccountEmptyState(title: String, subtitle: String, systemImage: String) -> some View {
    VStack(spacing: 14) {
        Image(systemName: systemImage)
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(TBTheme.skyBlue)

        Text(title)
            .font(.tbSectionTitle)
            .foregroundStyle(TBTheme.deepSky)

        Text(subtitle)
            .font(.tbBody)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
