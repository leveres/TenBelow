import SwiftUI
import PhotosUI

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
                orderStore.orderSupportError = nil
                inquiryStore.inquiryError = nil
                await MarketplaceAuthSession.syncAfterIdentityChange()
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

// MARK: - Cancel request sheet

struct CancelRequestSheet: View {
    @EnvironmentObject private var orderStore: OrderStore
    @Environment(\.dismiss) private var dismiss

    let order: Order
    let shipment: Shipment

    private static let presets = [
        "Changed my mind",
        "Ordered by mistake",
        "Found a better price",
        "Shipping taking too long",
        "Other…",
    ]

    @State private var selectedPreset: String? = nil
    @State private var customNote = ""
    @State private var isSubmitting = false

    private var isOther: Bool { selectedPreset == "Other…" }

    private var reasonToSubmit: String {
        if let preset = selectedPreset, preset != "Other…" { return preset }
        return customNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        guard let preset = selectedPreset else { return false }
        if preset == "Other…" {
            return customNote.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    warningBanner

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Why are you cancelling?")
                            .font(.tbBodyStrong)

                        FlowLayout(spacing: 8) {
                            ForEach(Self.presets, id: \.self) { preset in
                                Button {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        selectedPreset = preset
                                    }
                                } label: {
                                    Text(preset)
                                        .font(.system(size: 13, weight: .semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .foregroundStyle(selectedPreset == preset ? .white : .orange)
                                        .background(
                                            selectedPreset == preset ? Color.orange : Color.orange.opacity(0.07),
                                            in: Capsule(style: .continuous)
                                        )
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .strokeBorder(Color.orange.opacity(selectedPreset == preset ? 0 : 0.35), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if isOther {
                        TextField("Describe your reason (required)", text: $customNote, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    whatHappensNextCard

                    if let error = orderStore.orderSupportError, !error.isEmpty {
                        Text(error)
                            .font(.tbCaption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Send cancellation request")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                    .tint(.orange)
                    .disabled(!canSubmit || isSubmitting)
                }
                .padding(16)
                .animation(.easeOut(duration: 0.15), value: isOther)
            }
            .navigationTitle("Request cancellation")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(isSubmitting)
                }
            }
        }
    }

    private var warningBanner: some View {
        PolicyNoticeCard(
            title: MarketplacePolicyCopy.buyerCancelNotGuaranteedTitle,
            bodyText: MarketplacePolicyCopy.buyerCancelNotGuaranteedBody(sellerName: shipment.sellerName),
            tone: .caution
        )
    }

    private var whatHappensNextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What happens next")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                stepRow(number: "1", text: "Your request is sent to \(shipment.sellerName)")
                stepRow(number: "2", text: "They approve or deny — you'll get a notification")
                stepRow(number: "3", text: "If approved, this shipment is marked cancelled")
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TBTheme.frostEdge, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.orange.opacity(0.75), in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        await orderStore.createSupportRequest(
            orderId: order.id,
            type: .cancel,
            sellerId: shipment.sellerId,
            shipmentId: shipment.id,
            reason: reasonToSubmit
        )
        if orderStore.orderSupportError == nil { dismiss() }
    }
}

// MARK: - Refund request sheet

struct RefundRequestSheet: View {
    @EnvironmentObject private var orderStore: OrderStore
    @Environment(\.dismiss) private var dismiss

    let order: Order
    let shipment: Shipment

    @State private var selectedReasonCode: ExchangeReasonCode?
    @State private var reason = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickedImages: [UIImage] = []
    @State private var pickedVideoData: Data?
    @State private var pickedVideoExtension: String = "mp4"
    @State private var isSubmitting = false
    @State private var uploadProgress: String?

    private let maxImages = 3

    private var canSubmit: Bool {
        selectedReasonCode != nil
            && reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
            && !pickedImages.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Refund request")
                        .font(.tbSectionTitle)
                        .foregroundStyle(TBTheme.deepSky)

                    PolicyNoticeCard(
                        bodyText: MarketplacePolicyCopy.buyerRefundIntro,
                        tone: .support
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("What went wrong?")
                            .font(.tbBodyStrong)

                        ForEach(ExchangeReasonCode.refundEligibleCases) { code in
                            refundReasonButton(for: code)
                        }
                    }

                    TextField("Describe the damage or defect (required)", text: $reason, axis: .vertical)
                        .lineLimit(4...8)
                        .padding(12)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    evidenceSection

                    if let error = orderStore.orderSupportError, !error.isEmpty {
                        Text(error).font(.tbCaption).foregroundStyle(.red)
                    }

                    if let progress = uploadProgress {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(progress).font(.tbCaption).foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Submit request").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                    .disabled(!canSubmit || isSubmitting)
                }
                .padding(16)
            }
            .navigationTitle("Order support")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
            }
            .onChange(of: pickerItems) { _, items in
                Task { await loadPickedItems(items) }
            }
        }
    }

    private func refundReasonButton(for code: ExchangeReasonCode) -> some View {
        let isSelected = selectedReasonCode == code
        let selectionColor = isSelected ? TBTheme.deepSky : Color.secondary
        let backgroundColor = isSelected ? TBTheme.deepSky.opacity(0.08) : Color.white.opacity(0.55)
        let borderStyle = isSelected
            ? AnyShapeStyle(TBTheme.deepSky.opacity(0.24))
            : AnyShapeStyle(TBTheme.frostEdge)

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedReasonCode = code
            }
        } label: {
            refundReasonLabel(
                for: code,
                isSelected: isSelected,
                selectionColor: selectionColor,
                backgroundColor: backgroundColor,
                borderStyle: borderStyle
            )
        }
        .buttonStyle(.plain)
    }

    private func refundReasonLabel(
        for code: ExchangeReasonCode,
        isSelected: Bool,
        selectionColor: Color,
        backgroundColor: Color,
        borderStyle: AnyShapeStyle
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(selectionColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(code.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(code.helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderStyle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky)
                Text("Attach photos or video")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky)
                Spacer()
                Text("Required · at least 1 photo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !pickedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(pickedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(TBTheme.frostEdge, lineWidth: 1)
                                    )
                                Button {
                                    pickedImages.remove(at: index)
                                    if index < pickerItems.count { pickerItems.remove(at: index) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white)
                                        .background(Color.black.opacity(0.45), in: Circle())
                                }
                                .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if pickedVideoData != nil {
                HStack(spacing: 8) {
                    Image(systemName: "video.fill").foregroundStyle(TBTheme.deepSky)
                    Text("Video attached").font(.caption.weight(.semibold))
                    Spacer()
                    Button {
                        pickedVideoData = nil
                        pickerItems = []
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if pickedImages.count < maxImages && pickedVideoData == nil {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: maxImages - pickedImages.count,
                    matching: .any(of: [.images, .videos])
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle").font(.system(size: 14, weight: .semibold))
                        Text(pickedImages.isEmpty ? "Add photos or video" : "Add more photos")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(TBTheme.deepSky)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(TBTheme.deepSky.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(TBTheme.deepSky.opacity(0.22), lineWidth: 1)
                    )
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TBTheme.frostEdge, lineWidth: 1)
        )
    }

    private func loadPickedItems(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        var videoData: Data?
        var videoExt = "mp4"
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                if let image = UIImage(data: data) {
                    images.append(image)
                } else {
                    videoData = data
                    if let id = item.itemIdentifier, id.lowercased().hasSuffix(".mov") { videoExt = "mov" }
                }
            }
        }
        await MainActor.run {
            if !images.isEmpty {
                pickedImages = images; pickedVideoData = nil
            } else if let vd = videoData {
                pickedVideoData = vd; pickedVideoExtension = videoExt; pickedImages = []
            }
        }
    }

    private func submit() async {
        guard let selectedReasonCode else { return }
        guard !pickedImages.isEmpty else {
            orderStore.orderSupportError = "Attach at least one photo showing the damage."
            return
        }

        isSubmitting = true
        uploadProgress = nil
        defer { isSubmitting = false; uploadProgress = nil }

        let requestId = await orderStore.createSupportRequest(
            orderId: order.id,
            type: .refund,
            sellerId: shipment.sellerId,
            shipmentId: shipment.id,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            reasonCode: selectedReasonCode.rawValue
        )
        guard orderStore.orderSupportError == nil else { return }

        if let requestId {
            for (index, image) in pickedImages.enumerated() {
                uploadProgress = "Uploading photo \(index + 1) of \(pickedImages.count)…"
                guard let jpeg = image.jpegData(compressionQuality: 0.82) else { continue }
                _ = try? await OrdersAPI.uploadSupportEvidence(
                    orderId: order.id, requestId: requestId,
                    data: jpeg, contentType: "image/jpeg", fileExtension: "jpg", proofType: "image"
                )
            }
            if let videoData = pickedVideoData {
                uploadProgress = "Uploading video…"
                let mime = pickedVideoExtension == "mov" ? "video/quicktime" : "video/mp4"
                _ = try? await OrdersAPI.uploadSupportEvidence(
                    orderId: order.id, requestId: requestId,
                    data: videoData, contentType: mime, fileExtension: pickedVideoExtension, proofType: "video"
                )
            }
        }
        dismiss()
    }
}

// MARK: - Routing wrapper (keeps existing call sites unchanged)

struct OrderSupportRequestSheet: View {
    @EnvironmentObject private var orderStore: OrderStore
    let order: Order
    let shipment: Shipment
    let requestType: OrderSupportRequestType

    var body: some View {
        switch requestType {
        case .cancel:
            CancelRequestSheet(order: order, shipment: shipment)
                .environmentObject(orderStore)
        case .refund:
            RefundRequestSheet(order: order, shipment: shipment)
                .environmentObject(orderStore)
        }
    }
}

struct OrderSupportRequestsSection: View {
    @EnvironmentObject private var orderStore: OrderStore

    let order: Order
    let sellerId: String?
    let isSellerView: Bool
    var embeddedInCard: Bool = false

    @State private var requestPendingApproval: OrderSupportRequest?
    @State private var updatingRequestIDs: Set<String> = []

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

            if request.type == .cancel {
                HStack(spacing: 6) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.7))
                    Text("Reason: \(request.reason)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
                )
            } else {
                if let reasonCode = request.reasonCode,
                   let code = ExchangeReasonCode(rawValue: reasonCode) {
                    Text(code.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TBTheme.deepSky)
                }
                Text(request.reason)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isSellerView, request.status == .pending {
                if request.type == .cancel {
                    Text("Approving cancels this shipment for the buyer. This can't be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let isUpdating = updatingRequestIDs.contains(request.id)
                HStack(spacing: 8) {
                    Button {
                        if request.type == .cancel {
                            requestPendingApproval = request
                        } else {
                            resolve(request, as: .approved)
                        }
                    } label: {
                        if isUpdating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(request.type == .cancel ? "Approve & Cancel" : "Approve")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isUpdating)

                    Button("Deny") {
                        resolve(request, as: .denied)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUpdating)
                }
                .confirmationDialog(
                    "Cancel this shipment?",
                    isPresented: Binding(
                        get: { requestPendingApproval?.id == request.id },
                        set: { if !$0 { requestPendingApproval = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Approve cancellation", role: .destructive) {
                        requestPendingApproval = nil
                        resolve(request, as: .approved)
                    }
                    Button("Keep order", role: .cancel) {
                        requestPendingApproval = nil
                    }
                } message: {
                    Text("The shipment will be marked cancelled and the buyer will see it in their order. This can't be undone.")
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

    private func resolve(_ request: OrderSupportRequest, as status: OrderSupportRequestStatus) {
        guard !updatingRequestIDs.contains(request.id) else { return }
        updatingRequestIDs.insert(request.id)
        Task {
            await orderStore.updateSupportRequest(
                orderId: order.id,
                requestId: request.id,
                status: status
            )
            updatingRequestIDs.remove(request.id)
        }
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

// MARK: - FlowLayout (wrapping chip rows)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.origins[index].x, y: bounds.minY + result.origins[index].y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += lineHeight + spacing; lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: maxWidth, height: y + lineHeight), origins)
    }
}
