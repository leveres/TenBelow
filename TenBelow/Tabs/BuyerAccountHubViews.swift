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
        .background(TBFrostBackground())
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
    @State private var inboxFilter: MessageInboxFilter = .conversations
    @State private var inboxRevision = 0

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var inboxOwner: String {
        let email = buyerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return email.isEmpty ? "buyer" : "buyer:\(email)"
    }

    private var inboxEntries: [MessagingInboxEntry] {
        MessagingInbox.buyerEntries(
            orders: orderStore.orders,
            inquiryThreads: inquiryStore.buyerThreads,
            sellerProfiles: catalog.sellerProfiles,
            storefrontProducts: storefrontProducts
        )
    }

    private var visibleInboxEntries: [MessagingInboxEntry] {
        _ = inboxRevision
        return MessageInboxOrganizer.visibleEntries(
            inboxEntries,
            filter: inboxFilter,
            owner: inboxOwner,
            viewerIsBuyer: true
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
                    VStack(spacing: 12) {
                        MessageInboxFilterBar(
                            filter: $inboxFilter,
                            archivedCount: MessageInboxOrganizer.hiddenCount(in: inboxEntries, owner: inboxOwner),
                            onClearOld: {
                                MessageInboxOrganizer.hide(
                                    MessageInboxOrganizer.oldEntryIDs(in: inboxEntries),
                                    owner: inboxOwner
                                )
                                inboxRevision += 1
                            },
                            onRestoreArchived: {
                                MessageInboxOrganizer.restoreHidden(owner: inboxOwner)
                                inboxRevision += 1
                            }
                        )

                        if visibleInboxEntries.isEmpty {
                            Text(emptyFilterMessage)
                                .font(.tbBody)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 18)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(visibleInboxEntries) { entry in
                                    NavigationLink {
                                        messagingThreadView(for: entry)
                                            .onAppear {
                                                MessageInboxOrganizer.markRead(entry.id, owner: inboxOwner, at: entry.lastMessageDate)
                                                inboxRevision += 1
                                            }
                                    } label: {
                                        MessagingInboxRow(
                                            entry: entry,
                                            isUnread: MessageInboxOrganizer.isUnread(entry, viewerIsBuyer: true, owner: inboxOwner)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            MessageInboxOrganizer.hide([entry.id], owner: inboxOwner)
                                            inboxRevision += 1
                                        } label: {
                                            Label("Hide from inbox", systemImage: "archivebox")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TBFrostBackground())
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

    private var emptyFilterMessage: String {
        switch inboxFilter {
        case .unread:
            return "No unread messages."
        case .recent:
            return "No messages from the last 30 days."
        case .conversations:
            return "No conversations yet. New order chats show up here after the first message."
        case .all:
            return "Nothing in this inbox."
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
    @State private var inboxFilter: MessageInboxFilter = .conversations
    @State private var inboxRevision = 0

    private var inboxOwner: String {
        let sellerID = seller.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return sellerID.isEmpty ? "seller" : "seller:\(sellerID)"
    }

    private var inboxEntries: [MessagingInboxEntry] {
        MessagingInbox.sellerEntries(
            orders: orderStore.orders,
            inquiryThreads: inquiryStore.sellerThreads,
            sellerId: seller.id
        )
    }

    private var visibleInboxEntries: [MessagingInboxEntry] {
        _ = inboxRevision
        return MessageInboxOrganizer.visibleEntries(
            inboxEntries,
            filter: inboxFilter,
            owner: inboxOwner,
            viewerIsBuyer: false
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
                    VStack(spacing: 12) {
                        MessageInboxFilterBar(
                            filter: $inboxFilter,
                            archivedCount: MessageInboxOrganizer.hiddenCount(in: inboxEntries, owner: inboxOwner),
                            onClearOld: {
                                MessageInboxOrganizer.hide(
                                    MessageInboxOrganizer.oldEntryIDs(in: inboxEntries),
                                    owner: inboxOwner
                                )
                                inboxRevision += 1
                            },
                            onRestoreArchived: {
                                MessageInboxOrganizer.restoreHidden(owner: inboxOwner)
                                inboxRevision += 1
                            }
                        )

                        if visibleInboxEntries.isEmpty {
                            Text("No messages in this view.")
                                .font(.tbBody)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 18)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(visibleInboxEntries) { entry in
                                    NavigationLink {
                                        sellerMessagingThreadView(for: entry)
                                            .onAppear {
                                                MessageInboxOrganizer.markRead(entry.id, owner: inboxOwner, at: entry.lastMessageDate)
                                                inboxRevision += 1
                                            }
                                    } label: {
                                        MessagingInboxRow(
                                            entry: entry,
                                            isSellerInbox: true,
                                            isUnread: MessageInboxOrganizer.isUnread(entry, viewerIsBuyer: false, owner: inboxOwner)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            MessageInboxOrganizer.hide([entry.id], owner: inboxOwner)
                                            inboxRevision += 1
                                        } label: {
                                            Label("Hide from inbox", systemImage: "archivebox")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TBFrostBackground())
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

private struct MessageInboxFilterBar: View {
    @Binding var filter: MessageInboxFilter
    let archivedCount: Int
    let onClearOld: () -> Void
    let onRestoreArchived: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MessageInboxFilter.allCases) { option in
                        Button {
                            filter = option
                        } label: {
                            Text(option.rawValue)
                                .font(.tbCaption.weight(.semibold))
                                .foregroundStyle(filter == option ? .white : TBTheme.deepSky)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    filter == option ? TBTheme.deepSky : Color.white.opacity(0.72),
                                    in: Capsule(style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text("Long-press a thread to hide it.")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Menu {
                    Button("Clear messages older than 30 days", action: onClearOld)
                    if archivedCount > 0 {
                        Button("Restore hidden (\(archivedCount))", action: onRestoreArchived)
                    }
                } label: {
                    Text("Manage")
                        .font(.tbCaption.weight(.semibold))
                        .foregroundStyle(TBTheme.icyBlue)
                }
            }
        }
    }
}

struct MessagingInboxRow: View {
    let entry: MessagingInboxEntry
    var isSellerInbox: Bool = false
    var isUnread: Bool = false

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

                    Text(entry.lastMessageDate.formatted(.relative(presentation: .named)))
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if isUnread {
                        Circle()
                            .fill(TBTheme.accent)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(entry.contextLabel)
                    .font(.tbCaption)
                    .foregroundStyle(TBTheme.icyBlue)
                    .lineLimit(1)

                Text(entry.hasConversation ? entry.lastMessageText : "No messages yet")
                    .font(.tbBody)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
                .strokeBorder(isUnread ? TBTheme.accent.opacity(0.28) : .white.opacity(0.72), lineWidth: 1)
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
