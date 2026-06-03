import SwiftUI

struct OrderSupportThreadView: View {
    @EnvironmentObject private var orderStore: OrderStore
    @EnvironmentObject private var inquiryStore: SellerInquiryStore
    @Environment(\.dismiss) private var dismiss

    let orderId: String?
    let sellerId: String
    let sellerName: String
    let viewerRole: OrdersMode
    /// When the seller opens a shop inquiry, which buyer email to load.
    var inquiryBuyerEmail: String?

    private var isShopInquiry: Bool { orderId == nil }

    init(
        orderId: String,
        sellerId: String,
        sellerName: String,
        viewerRole: OrdersMode
    ) {
        self.orderId = orderId
        self.sellerId = sellerId
        self.sellerName = sellerName
        self.viewerRole = viewerRole
        self.inquiryBuyerEmail = nil
    }

    init(
        sellerId: String,
        sellerName: String,
        viewerRole: OrdersMode,
        inquiryBuyerEmail: String? = nil
    ) {
        self.orderId = nil
        self.sellerId = sellerId
        self.sellerName = sellerName
        self.viewerRole = viewerRole
        self.inquiryBuyerEmail = inquiryBuyerEmail
    }

    @State private var messages: [OrderSupportMessage] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 24)
                            } else if messages.isEmpty {
                                Text(emptyThreadHint)
                                    .font(.tbBody)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                            } else {
                                ForEach(messages) { message in
                                    supportBubble(message)
                                        .id(message.id)
                                }
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last?.id {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }

                if let error = activeError, !error.isEmpty {
                    Text(error)
                        .font(.tbCaption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }

                HStack(spacing: 10) {
                    TextField("Write a message", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(12)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        Task { await sendMessage() }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TBTheme.icyBlue)
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
                .background(.ultraThinMaterial)
            }
            .navigationTitle(navigationTitle)
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: threadTaskKey) {
                isLoading = true
                messages = await loadMessages()
                isLoading = false
            }
            .onChange(of: orderStore.orders) { _, _ in
                guard !isShopInquiry else { return }
                syncOrderMessagesFromStore()
            }
            .onChange(of: inquiryStore.buyerThreads) { _, _ in
                guard isShopInquiry, viewerRole == .buyer else { return }
                syncInquiryMessagesFromStore()
            }
            .onChange(of: inquiryStore.sellerThreads) { _, _ in
                guard isShopInquiry, viewerRole == .seller else { return }
                syncInquiryMessagesFromStore()
            }
        }
    }

    private var navigationTitle: String {
        isShopInquiry ? "Message \(sellerName)" : "\(sellerName) support"
    }

    private var emptyThreadHint: String {
        if isShopInquiry {
            return "No messages yet. Ask about products, materials, shipping, or custom options."
        }
        return "No messages yet. Use this thread for order updates, shipping questions, or support."
    }

    private var threadTaskKey: String {
        if let orderId {
            return "order|\(orderId)|\(sellerId)"
        }
        let buyerKey = inquiryBuyerEmail ?? "buyer"
        return "inquiry|\(sellerId)|\(buyerKey)"
    }

    private var activeError: String? {
        if isShopInquiry {
            return inquiryStore.inquiryError
        }
        return orderStore.orderSupportError
    }

    private func loadMessages() async -> [OrderSupportMessage] {
        if let orderId {
            return await orderStore.fetchSupportThread(orderId: orderId, sellerId: sellerId)
        }
        return await inquiryStore.fetchThread(sellerId: sellerId, buyerEmail: inquiryBuyerEmail)
    }

    private func syncOrderMessagesFromStore() {
        guard let orderId, let order = orderStore.order(withId: orderId) else { return }
        let synced = order.orderMessages
            .filter { $0.sellerId == sellerId }
            .sorted { $0.createdAt < $1.createdAt }
        guard !synced.isEmpty || !isLoading else { return }
        messages = synced
    }

    private func syncInquiryMessagesFromStore() {
        guard let thread = inquiryStore.thread(for: sellerId, buyerEmail: inquiryBuyerEmail) else { return }
        let synced = thread.messages.sorted { $0.createdAt < $1.createdAt }
        guard !synced.isEmpty || !isLoading else { return }
        messages = synced
    }

    @ViewBuilder
    private func supportBubble(_ message: OrderSupportMessage) -> some View {
        let isMine = viewerRole == .buyer ? message.isFromBuyer : !message.isFromBuyer
        HStack {
            if isMine { Spacer(minLength: 36) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.tbBody)
                    .foregroundStyle(isMine ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        isMine ? TBTheme.deepSky : Color.white.opacity(0.82),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                Text(message.timestampLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !isMine { Spacer(minLength: 36) }
        }
    }

    private func sendMessage() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        defer { isSending = false }

        let senderName: String? = viewerRole == .buyer
            ? UserDefaults.standard.string(forKey: "buyerFullName")
            : nil
        let updated: [OrderSupportMessage]
        if let orderId {
            updated = await orderStore.sendSupportMessage(
                orderId: orderId,
                sellerId: sellerId,
                text: trimmed,
                senderName: senderName
            )
        } else {
            updated = await inquiryStore.sendMessage(
                sellerId: sellerId,
                text: trimmed,
                senderName: senderName,
                buyerEmail: inquiryBuyerEmail
            )
        }
        if !updated.isEmpty {
            messages = updated
            draft = ""
        }
    }
}

struct OrderSupportRequestSheet: View {
    @EnvironmentObject private var orderStore: OrderStore
    @Environment(\.dismiss) private var dismiss

    let order: Order
    let shipment: Shipment
    let requestType: OrderSupportRequestType

    @State private var reason = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(requestType.title)
                        .font(.tbSectionTitle)
                        .foregroundStyle(TBTheme.deepSky)

                    Text(helperCopy)
                        .font(.tbBody)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Describe the issue (required)", text: $reason, axis: .vertical)
                        .lineLimit(4...8)
                        .padding(12)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if let error = orderStore.orderSupportError, !error.isEmpty {
                        Text(error)
                            .font(.tbCaption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Text("Submit request")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                }
                .padding(16)
            }
            .navigationTitle("Order support")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var helperCopy: String {
        switch requestType {
        case .cancel:
            return "This sends a cancel request to \(shipment.sellerName) before the package ships. The seller can approve or deny it."
        case .refund:
            return "Use this after shipping if something arrived damaged, defective, or not as described. Refunds are reviewed by the seller."
        }
    }

    private func submit() async {
        await orderStore.createSupportRequest(
            orderId: order.id,
            type: requestType,
            sellerId: shipment.sellerId,
            shipmentId: shipment.id,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if orderStore.orderSupportError == nil {
            dismiss()
        }
    }
}

struct OrderSupportRequestsSection: View {
    @EnvironmentObject private var orderStore: OrderStore

    let order: Order
    let sellerId: String?
    let isSellerView: Bool
    var embeddedInCard: Bool = false

    var body: some View {
        let requests = filteredRequests
        if requests.isEmpty && !isSellerView {
            return AnyView(EmptyView())
        }

        let content = VStack(alignment: .leading, spacing: 12) {
            if !embeddedInCard {
                Text("Support requests")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            if requests.isEmpty {
                Text("No open support requests for this order.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(requests) { request in
                    supportRequestRow(request)
                }
            }
        }

        if embeddedInCard {
            return AnyView(content)
        }
        return AnyView(GlassCard(cornerRadius: 20) { content })
    }

    @ViewBuilder
    private func supportRequestRow(_ request: OrderSupportRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(request.type.title)
                    .font(.tbBodyStrong)
                Spacer()
                Text(request.status.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusTint(request.status).opacity(0.14), in: Capsule())
            }
            Text(request.reason)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isSellerView, request.status == .pending {
                HStack(spacing: 8) {
                    Button("Approve") {
                        Task {
                            await orderStore.updateSupportRequest(
                                orderId: order.id,
                                requestId: request.id,
                                status: .approved
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button("Deny") {
                        Task {
                            await orderStore.updateSupportRequest(
                                orderId: order.id,
                                requestId: request.id,
                                status: .denied
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else if !isSellerView, request.status == .pending, request.requestedBy == "buyer" {
                Button("Withdraw request") {
                    Task {
                        await orderStore.updateSupportRequest(
                            orderId: order.id,
                            requestId: request.id,
                            status: .withdrawn
                        )
                    }
                }
                .font(.caption.weight(.semibold))
            }

            if let note = request.resolutionNote, !note.isEmpty {
                Text("Seller note: \(note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var filteredRequests: [OrderSupportRequest] {
        if let sellerId {
            return order.supportRequests.filter { $0.sellerId == sellerId }
        }
        return order.supportRequests
    }

    private func statusTint(_ status: OrderSupportRequestStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .approved: return .green
        case .denied: return .red
        case .withdrawn: return .gray
        }
    }
}
