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
    @EnvironmentObject private var buyerSellerThreads: BuyerSellerThreadStore
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var threadEntries: [BuyerMessageThreadEntry] {
        buyerSellerThreads.sellerIdsOrderedByRecentMessage().compactMap { sellerId in
            guard
                let seller = resolvedSellerProfile(
                    sellerId: sellerId,
                    storefrontProducts: storefrontProducts.filter { $0.sellerId == sellerId },
                    remoteProfiles: catalog.sellerProfiles
                )
            else {
                return nil
            }

            let messages = buyerSellerThreads.messages(for: sellerId)
            let lastMessage = messages.last
            return BuyerMessageThreadEntry(
                seller: seller,
                lastMessageText: lastMessage?.text ?? "No messages yet",
                lastMessageTimestamp: lastMessage?.timestampLabel ?? ""
            )
        }
    }

    var body: some View {
        Group {
            if threadEntries.isEmpty {
                buyerAccountEmptyState(
                    title: "No messages yet",
                    subtitle: "Message a seller from their storefront to start a conversation here.",
                    systemImage: "bubble.left.and.bubble.right"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(threadEntries) { entry in
                            NavigationLink {
                                SellerMessagesView(seller: entry.seller)
                            } label: {
                                BuyerMessageThreadRow(entry: entry)
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
    }
}

struct SellerMessagesView: View {
    let seller: SellerProfile

    @EnvironmentObject private var threadStore: BuyerSellerThreadStore
    @State private var draftMessage = ""
    @State private var hasBootstrappedThread = false

    private var threadMessages: [BuyerSellerThreadMessage] {
        threadStore.messages(for: seller.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        messageHeaderCard

                        ForEach(threadMessages) { message in
                            SellerMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, TBTheme.spacingLG)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .onChange(of: threadMessages.count) { _, _ in
                    guard let last = threadMessages.last else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(red: 0.972, green: 0.981, blue: 0.993).ignoresSafeArea())
        .navigationTitle("Messages")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            messageComposer
        }
        .onAppear {
            guard !hasBootstrappedThread else { return }
            hasBootstrappedThread = true
            threadStore.bootstrapThreadIfNeeded(sellerId: seller.id, sellerDisplayName: seller.displayName)
        }
    }

    private var messageHeaderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message \(seller.displayName)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.88))

            Text("Ask about materials, shipping, or custom options.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                Text("Typical reply within a few hours")
                    .font(.caption)
            }
            .foregroundStyle(.secondary.opacity(0.9))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, y: 4)
    }

    private var messageComposer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Write a message...", text: $draftMessage, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.98), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                    )

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.36, green: 0.60, blue: 0.93),
                                    Color(red: 0.24, green: 0.47, blue: 0.78)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            }

            Text("Messages in this preview are saved on this device.")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, TBTheme.spacingLG)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(
            Color.white.opacity(0.92)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
        }
    }

    private func sendMessage() {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        threadStore.appendBuyerMessage(sellerId: seller.id, text: trimmed)
        draftMessage = ""
    }
}

struct SellerInboxListView: View {
    let seller: SellerProfile

    @EnvironmentObject private var buyerSellerThreads: BuyerSellerThreadStore
    @State private var selectedThread: SellerInboxThreadEntry?

    private var threads: [SellerInboxThreadEntry] {
        buyerSellerThreads.threadsForSellerOrderedByRecentMessage(sellerId: seller.id)
    }

    var body: some View {
        Group {
            if threads.isEmpty {
                buyerAccountEmptyState(
                    title: "No buyer messages yet",
                    subtitle: "When buyers message your store, conversations will appear here.",
                    systemImage: "bubble.left.and.bubble.right"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(threads) { thread in
                            Button {
                                selectedThread = thread
                            } label: {
                                SellerInboxThreadRow(thread: thread)
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
        .navigationDestination(item: $selectedThread) { thread in
            SellerInboxConversationView(seller: seller, thread: thread)
        }
    }
}

struct SellerInboxConversationView: View {
    let seller: SellerProfile
    let thread: SellerInboxThreadEntry

    @EnvironmentObject private var threadStore: BuyerSellerThreadStore
    @State private var draftMessage = ""

    private var threadMessages: [BuyerSellerThreadMessage] {
        threadStore.messages(for: seller.id, buyerIdentity: thread.buyerIdentity)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        sellerConversationHeader

                        ForEach(threadMessages) { message in
                            SellerMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, TBTheme.spacingLG)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .onChange(of: threadMessages.count) { _, _ in
                    guard let last = threadMessages.last else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(red: 0.972, green: 0.981, blue: 0.993).ignoresSafeArea())
        .navigationTitle(thread.buyerDisplayName)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            sellerMessageComposer
        }
    }

    private var sellerConversationHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conversation with \(thread.buyerDisplayName)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.88))

            Text("Reply as \(seller.displayName) about orders, materials, or custom options.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            HStack(spacing: 8) {
                Image(systemName: "storefront")
                    .font(.system(size: 11, weight: .semibold))
                Text("Messages stay connected to this store thread")
                    .font(.caption)
            }
            .foregroundStyle(.secondary.opacity(0.9))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, y: 4)
    }

    private var sellerMessageComposer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Reply to buyer...", text: $draftMessage, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.98), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                    )

                Button {
                    sendSellerMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.36, green: 0.60, blue: 0.93),
                                    Color(red: 0.24, green: 0.47, blue: 0.78)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            }
        }
        .padding(.horizontal, TBTheme.spacingLG)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(
            Color.white.opacity(0.92)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
        }
    }

    private func sendSellerMessage() {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        threadStore.appendSellerMessage(
            sellerId: seller.id,
            buyerIdentity: thread.buyerIdentity,
            text: trimmed
        )
        draftMessage = ""
    }
}

private struct BuyerMessageThreadEntry: Identifiable {
    let seller: SellerProfile
    let lastMessageText: String
    let lastMessageTimestamp: String

    var id: String { seller.id }
}

private struct BuyerMessageThreadRow: View {
    let entry: BuyerMessageThreadEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TBTheme.deepSky)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.seller.displayName)
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

struct SellerMessageBubble: View {
    let message: BuyerSellerThreadMessage

    var body: some View {
        VStack(alignment: message.isFromBuyer ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.isFromBuyer { Spacer(minLength: 40) }

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.isFromBuyer ? .white : .primary.opacity(0.84))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(messageBubbleFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                message.isFromBuyer ? Color.clear : TBTheme.skyBlue.opacity(0.10),
                                lineWidth: 1
                            )
                    )

                if !message.isFromBuyer { Spacer(minLength: 40) }
            }

            Text(message.timestampLabel)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var messageBubbleFill: AnyShapeStyle {
        if message.isFromBuyer {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.36, green: 0.60, blue: 0.93),
                        Color(red: 0.24, green: 0.47, blue: 0.78)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    .white.opacity(0.98),
                    Color(red: 0.965, green: 0.982, blue: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct SellerInboxThreadRow: View {
    let thread: SellerInboxThreadEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "storefront")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TBTheme.deepSky)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(thread.buyerDisplayName)
                        .font(.tbBodyStrong)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if !thread.lastMessageTimestamp.isEmpty {
                        Text(thread.lastMessageTimestamp)
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(thread.lastMessageText)
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
