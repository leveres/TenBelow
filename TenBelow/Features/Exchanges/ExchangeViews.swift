import SwiftUI
import PhotosUI

private enum ExchangeFlowStep: Hashable {
    case reason
    case proof
    case review
    case confirmation(String)
    case status(String)
}

struct ExchangeRequestFlowSheet: View {
    @EnvironmentObject private var exchangeStore: ExchangeStore
    @EnvironmentObject private var catalog: CatalogStore

    let order: Order
    let items: [ExchangeOrderItemContext]

    var body: some View {
        ExchangeRequestFlowContainer(
            order: order,
            items: items,
            exchangeStore: exchangeStore,
            config: catalog.config
        )
    }
}

private struct ExchangeRequestFlowContainer: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ExchangeRequestViewModel
    @State private var path: [ExchangeFlowStep] = []

    init(order: Order, items: [ExchangeOrderItemContext], exchangeStore: ExchangeStore, config: AppConfig) {
        _viewModel = StateObject(
            wrappedValue: ExchangeRequestViewModel(
                order: order,
                availableItems: items,
                exchangeStore: exchangeStore,
                config: config
            )
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            ExchangeIntroView(
                viewModel: viewModel,
                onContinue: { path.append(.reason) }
            )
            .navigationDestination(for: ExchangeFlowStep.self) { step in
                switch step {
                case .reason:
                    ExchangeReasonView(
                        viewModel: viewModel,
                        onContinue: { path.append(.proof) }
                    )
                case .proof:
                    ExchangeProofUploadView(
                        viewModel: viewModel,
                        onContinue: { path.append(.review) }
                    )
                case .review:
                    ExchangeReviewSubmitView(
                        viewModel: viewModel,
                        onSubmitted: { requestId in
                            path.append(.confirmation(requestId))
                        }
                    )
                case .confirmation(let requestId):
                    ExchangeSubmittedConfirmationView(
                        requestId: requestId,
                        onTrackRequest: {
                            path.append(.status(requestId))
                        },
                        onBackToOrder: {
                            dismiss()
                        }
                    )
                case .status(let requestId):
                    ExchangeStatusScreen(exchangeRequestId: requestId)
                }
            }
        }
    }
}

private struct ExchangeIntroView: View {
    @ObservedObject var viewModel: ExchangeRequestViewModel
    let onContinue: () -> Void
    @State private var showExchangePolicyBrowser = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                GlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Request an Exchange")
                            .font(.tbProductTitleXL)
                            .foregroundStyle(TBTheme.deepSky)

                        PolicyNoticeCard(
                            bodyText: MarketplacePolicyCopy.buyerExchangeIntro,
                            tone: .exchange
                        )

                        Text("Select the item you'd like reviewed.")
                            .font(.tbBodyStrong)
                            .foregroundStyle(TBTheme.deepSky)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.selectableItems) { context in
                        ExchangeSelectableItemCard(
                            context: context,
                            isSelected: context.id == viewModel.selectedItemId
                        )
                        .onTapGesture {
                            viewModel.selectItem(context.id)
                        }
                    }
                }

                Button {
                    showExchangePolicyBrowser = true
                } label: {
                    Text(MarketplacePolicyCopy.readExchangePolicyButton)
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.icyBlue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
            }
            .padding(16)
        }
        .background(TBFrostBackground())
        .navigationTitle("Exchange")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showExchangePolicyBrowser) {
            LegalDocumentSheet(document: .exchangePolicy)
        }
    }
}

private struct ExchangeReasonView: View {
    @ObservedObject var viewModel: ExchangeRequestViewModel
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                GlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What happened?")
                            .font(.tbProductTitleXL)
                            .foregroundStyle(TBTheme.deepSky)

                        Text("Tell us what went wrong so we can review the item quickly.")
                            .font(.tbBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(ExchangeReasonCode.allCases) { reason in
                        Button {
                            viewModel.selectedReasonCode = reason
                            viewModel.persistDraft()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(reason.title)
                                    .font(.tbBodyStrong)
                                    .foregroundStyle(TBTheme.deepSky)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(reason.helperText)
                                    .font(.tbCaption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.white.opacity(0.82))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(
                                        viewModel.selectedReasonCode == reason
                                            ? TBTheme.icyBlue.opacity(0.8)
                                            : TBTheme.skyBlue.opacity(0.16),
                                        lineWidth: viewModel.selectedReasonCode == reason ? 1.5 : 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                GlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Explain the issue")
                                .font(.tbBodyStrong)
                                .foregroundStyle(TBTheme.deepSky)
                            Spacer()
                            Text("\(viewModel.explanationCharacterCount)/400")
                                .font(.tbCaption)
                                .foregroundStyle(.secondary)
                        }

                        TextEditor(text: $viewModel.buyerExplanation)
                            .frame(minHeight: 150)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(TBTheme.cloudWhite)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(TBTheme.skyBlue.opacity(0.16), lineWidth: 1)
                            )
                            .onChange(of: viewModel.buyerExplanation) { _, newValue in
                                if newValue.count > 400 {
                                    viewModel.buyerExplanation = String(newValue.prefix(400))
                                }
                                viewModel.persistDraft()
                            }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.tbCaption)
                        .foregroundStyle(.red)
                }

                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                .disabled(!viewModel.canContinueFromReason)
                .opacity(viewModel.canContinueFromReason ? 1 : 0.55)
            }
            .padding(16)
        }
        .background(TBFrostBackground())
        .navigationTitle("Reason")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct ExchangeProofUploadView: View {
    @ObservedObject var viewModel: ExchangeRequestViewModel
    let onContinue: () -> Void

    @State private var selectedImageItems: [PhotosPickerItem] = []
    @State private var selectedVideoItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                GlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Upload proof")
                            .font(.tbProductTitleXL)
                            .foregroundStyle(TBTheme.deepSky)

                        Text("Please upload a few clear photos so we can review the issue.")
                            .font(.tbBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                GlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        PhotosPicker(
                            selection: $selectedImageItems,
                            maxSelectionCount: viewModel.config.maxProofImages,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Add photos", systemImage: "photo.on.rectangle.angled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: false))

                        if viewModel.config.allowProofVideo {
                            PhotosPicker(
                                selection: $selectedVideoItem,
                                matching: .videos,
                                photoLibrary: .shared()
                            ) {
                                Label("Add short video", systemImage: "video.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: false))
                        }

                        Text("Photos required: \(viewModel.config.minProofImages)-\(viewModel.config.maxProofImages).")
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)

                        DraftProofGalleryView(
                            assets: viewModel.draftAssets,
                            onRemove: { asset in
                                viewModel.removeAsset(asset)
                            }
                        )
                    }
                }

                if let proofMessage = viewModel.proofMessage {
                    Text(proofMessage)
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                }

                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                .disabled(!viewModel.canContinueFromProof)
                .opacity(viewModel.canContinueFromProof ? 1 : 0.55)
            }
            .padding(16)
        }
        .background(TBFrostBackground())
        .navigationTitle("Proof")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: selectedImageItems) { _, newItems in
            Task {
                await viewModel.loadSelectedImages(from: newItems)
            }
        }
        .onChange(of: selectedVideoItem) { _, newItem in
            Task {
                await viewModel.loadSelectedVideo(from: newItem)
            }
        }
    }
}

private struct ExchangeReviewSubmitView: View {
    @ObservedObject var viewModel: ExchangeRequestViewModel
    let onSubmitted: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                if let selectedItem = viewModel.selectedItem {
                    GlassCard(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Review request")
                                .font(.tbProductTitleXL)
                                .foregroundStyle(TBTheme.deepSky)

                            ExchangeSelectableItemCard(context: selectedItem, isSelected: true)

                            VStack(alignment: .leading, spacing: 6) {
                                reviewRow(title: "Order number", value: viewModel.order.id)
                                reviewRow(title: "Reason", value: viewModel.selectedReasonCode?.title ?? "Not selected")
                                reviewRow(title: "Explanation", value: viewModel.buyerExplanation)
                                reviewRow(title: "Photos", value: "\(viewModel.imageAssets.count)")
                                if viewModel.videoAsset != nil {
                                    reviewRow(title: "Video", value: "Included")
                                }
                            }
                        }
                    }
                }

                GlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Policy reminder")
                            .font(.tbBodyStrong)
                            .foregroundStyle(TBTheme.deepSky)

                        Text("Approved exchanges are replacements of the same item only.")
                            .font(.tbBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if viewModel.isSubmitting {
                    ProgressView(value: viewModel.submitProgress)
                        .tint(TBTheme.icyBlue)
                        .animation(nil, value: viewModel.isSubmitting)
                    Text("Uploading proof and submitting your request...")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.tbCaption)
                        .foregroundStyle(.red)
                }

                Button(viewModel.isSubmitting ? "Submitting..." : "Submit Request") {
                    Task {
                        await viewModel.submit()
                        if let requestId = viewModel.submittedRequest?.id {
                            onSubmitted(requestId)
                        }
                    }
                }
                .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))
                .disabled(!viewModel.canSubmit)
                .opacity(viewModel.canSubmit ? 1 : 0.55)
            }
            .padding(16)
        }
        .background(TBFrostBackground())
        .navigationTitle("Review")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func reviewRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.tbBodyStrong)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ExchangeSubmittedConfirmationView: View {
    let requestId: String
    let onTrackRequest: () -> Void
    let onBackToOrder: () -> Void

    var body: some View {
        VStack(spacing: TBTheme.spacingLG) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(TBTheme.icyBlue)

            Text("Your request has been submitted.")
                .font(.tbProductTitleXL)
                .foregroundStyle(TBTheme.deepSky)

            Text("We’re reviewing your exchange request now.")
                .font(.tbBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(requestId)
                .font(.tbCaption)
                .foregroundStyle(.tertiary)

            VStack(spacing: 10) {
                Button("Track Request") {
                    onTrackRequest()
                }
                .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true))

                Button("Back to Order") {
                    onBackToOrder()
                }
                .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: false))
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TBFrostBackground())
        .navigationTitle("Submitted")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct ExchangeStatusScreen: View {
    @EnvironmentObject private var exchangeStore: ExchangeStore
    let exchangeRequestId: String

    var body: some View {
        ExchangeStatusContainer(exchangeRequestId: exchangeRequestId, exchangeStore: exchangeStore)
    }
}

private struct ExchangeStatusContainer: View {
    @StateObject private var viewModel: ExchangeStatusViewModel

    init(exchangeRequestId: String, exchangeStore: ExchangeStore) {
        _viewModel = StateObject(
            wrappedValue: ExchangeStatusViewModel(
                exchangeRequestId: exchangeRequestId,
                exchangeStore: exchangeStore
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                if let request = viewModel.exchangeRequest {
                    GlassCard(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 14) {
                            ExchangeStatusPill(status: request.status)

                            Text(request.productTitle)
                                .font(.tbProductTitleXL)
                                .foregroundStyle(TBTheme.deepSky)

                            Text("Order \(request.orderId)")
                                .font(.tbCaption)
                                .foregroundStyle(.secondary)

                            Text(request.status.detailCopy)
                                .font(.tbBody)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let denialReason = request.denialReason, !denialReason.isEmpty {
                        GlassCard(cornerRadius: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Denial reason")
                                    .font(.tbBodyStrong)
                                    .foregroundStyle(TBTheme.deepSky)
                                Text(denialReason)
                                    .font(.tbBody)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    GlassCard(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Timeline")
                                .font(.tbBodyStrong)
                                .foregroundStyle(TBTheme.deepSky)

                            ForEach(request.timelineEvents.sorted { $0.createdAt > $1.createdAt }) { event in
                                TimelineRow(event: event)
                            }
                        }
                    }

                    if !request.buyerProofAssets.isEmpty {
                        GlassCard(cornerRadius: 24) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Proof")
                                    .font(.tbBodyStrong)
                                    .foregroundStyle(TBTheme.deepSky)

                                ProofGalleryView(assets: request.buyerProofAssets)
                            }
                        }
                    }

                    if let shippingCarrier = request.shippingCarrier ?? request.trackingNumber,
                       !shippingCarrier.isEmpty {
                        GlassCard(cornerRadius: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Replacement shipping")
                                    .font(.tbBodyStrong)
                                    .foregroundStyle(TBTheme.deepSky)

                                if let carrier = request.shippingCarrier, !carrier.isEmpty {
                                    Text("Carrier: \(carrier)")
                                        .font(.tbBody)
                                        .foregroundStyle(.secondary)
                                }
                                if let trackingNumber = request.trackingNumber, !trackingNumber.isEmpty {
                                    Text("Tracking: \(trackingNumber)")
                                        .font(.tbBody)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if ["awaiting_buyer_proof", "submitted"].contains(request.status.rawValue) {
                        Button("Cancel Request") {
                            Task {
                                await viewModel.cancelIfAllowed()
                            }
                        }
                        .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: false))
                    }
                } else if viewModel.isLoading {
                    ProgressView()
                        .tint(TBTheme.icyBlue)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.tbCaption)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .background(TBFrostBackground())
        .navigationTitle("Exchange Status")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await viewModel.load()
        }
    }
}

struct ExchangeStatusPill: View {
    let status: ExchangeRequestStatus

    var body: some View {
        Text(status.title)
            .font(.tbCaption)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor, in: Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .approved, .replacementPreparing, .replacementShipped, .replacementDelivered, .closed:
            return Color.green.opacity(0.16)
        case .denied, .cancelled:
            return Color.red.opacity(0.14)
        case .awaitingBuyerProof, .awaitingSellerResponse:
            return Color.orange.opacity(0.16)
        default:
            return TBTheme.skyBlue.opacity(0.16)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .approved, .replacementPreparing, .replacementShipped, .replacementDelivered, .closed:
            return Color.green
        case .denied, .cancelled:
            return Color.red
        case .awaitingBuyerProof, .awaitingSellerResponse:
            return Color.orange
        default:
            return TBTheme.deepSky
        }
    }
}

struct TimelineRow: View {
    let event: ExchangeTimelineEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(TBTheme.icyBlue)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.message)
                    .font(.tbBodyStrong)
                    .foregroundStyle(.primary)

                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProofGalleryView: View {
    let assets: [ExchangeProofAsset]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(assets) { asset in
                    if asset.type == .image, let url = URL(string: asset.url) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(TBTheme.skyBlue.opacity(0.12))
                                    .overlay {
                                        Image(systemName: "photo")
                                            .foregroundStyle(.secondary)
                                    }
                            }
                        }
                        .frame(width: 108, height: 108)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(TBTheme.skyBlue.opacity(0.10))
                            .frame(width: 108, height: 108)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(TBTheme.deepSky)
                                    Text("Video")
                                        .font(.tbCaption)
                                        .foregroundStyle(TBTheme.deepSky)
                                }
                            }
                    }
                }
            }
        }
    }
}

private struct DraftProofGalleryView: View {
    let assets: [ExchangeLocalDraftAsset]
    let onRemove: (ExchangeLocalDraftAsset) -> Void

    var body: some View {
        if assets.isEmpty {
            Text("No proof uploaded yet.")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(assets) { asset in
                        ZStack(alignment: .topTrailing) {
                            DraftProofThumbnail(asset: asset)
                                .frame(width: 96, height: 96)

                            Button {
                                onRemove(asset)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white, Color.black.opacity(0.55))
                            }
                            .offset(x: 6, y: -6)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

private struct DraftProofThumbnail: View {
    let asset: ExchangeLocalDraftAsset

    var body: some View {
        let previewPath = asset.thumbnailURLString ?? asset.localFileURLString
        Group {
            if asset.type == .image,
               let image = UIImage(contentsOfFile: previewPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(TBTheme.skyBlue.opacity(0.12))
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: asset.type == .video ? "video.fill" : "photo")
                                .foregroundStyle(TBTheme.deepSky)
                            Text(asset.type == .video ? "Video" : "Photo")
                                .font(.tbCaption)
                                .foregroundStyle(TBTheme.deepSky)
                        }
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ExchangeSelectableItemCard: View {
    let context: ExchangeOrderItemContext
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let imageURL = context.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(TBTheme.skyBlue.opacity(0.12))
                                .overlay {
                                    Image(systemName: "shippingbox.fill")
                                        .foregroundStyle(TBTheme.deepSky)
                                }
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(TBTheme.skyBlue.opacity(0.12))
                        .overlay {
                            Image(systemName: "shippingbox.fill")
                                .foregroundStyle(TBTheme.deepSky)
                        }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(context.productTitle)
                    .font(.tbBodyStrong)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(context.sellerName)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TBTheme.icyBlue)
            }
        }
        .padding(14)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isSelected ? TBTheme.icyBlue.opacity(0.8) : TBTheme.skyBlue.opacity(0.14),
                    lineWidth: isSelected ? 1.4 : 1
                )
        )
    }
}
