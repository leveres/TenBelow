//
//  DropSubmitView.swift
//  TenBelow
//

import SwiftUI
import Combine
import PhotosUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct DropSubmitView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("sellerSellerId") private var sellerId = ""
    @AppStorage("sellerPreviewMode") private var sellerPreviewMode = false
    @AppStorage("catalogRefreshToken") private var catalogRefreshToken = 0

    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore
    @EnvironmentObject private var catalog: CatalogStore

    private let currentDrop: CurrentDropResponse?
    private let referenceDate: Date
    private let usesPreviewData: Bool

    @StateObject private var viewModel: WeeklyDropPrepViewModel
    @State private var savedWeeklyDropComposer: WeeklyDropComposerDraft?
    @State private var isShowingDropComposerResumeDialog = false
    init(
        currentDrop: CurrentDropResponse? = nil,
        referenceDate: Date = .now,
        initialSubmissions: SellerSubmissionsResponse? = nil,
        usesPreviewData: Bool = false
    ) {
        self.currentDrop = currentDrop
        self.referenceDate = referenceDate
        self.usesPreviewData = usesPreviewData
        _viewModel = StateObject(
            wrappedValue: WeeklyDropPrepViewModel(initialSubmissions: initialSubmissions)
        )
    }

    private var hasDropAccess: Bool {
        true
    }

    private var isWindowOpen: Bool {
        if viewModel.submissions?.isActive == true {
            return true
        }
        return WeekendDropManager.isSubmissionWindowOpen(
            now: .now,
            currentDrop: currentDrop
        )
    }

    private var slotsUsed: Int {
        viewModel.submissions?.slotsUsed ?? 0
    }

    private var slotsMax: Int {
        viewModel.submissions?.slotsMax ?? DropConstants.maxSlotsPerSeller
    }

    private var slotsRemaining: Int {
        max(slotsMax - slotsUsed, 0)
    }

    private var canCreateDropProduct: Bool {
        isWindowOpen && slotsRemaining > 0
    }

    private var canEditExistingDropProducts: Bool {
        !viewModel.products.isEmpty
    }

    private var shouldShowPrimaryActionCard: Bool {
        canCreateDropProduct || canEditExistingDropProducts
    }

    var body: some View {
        GeometryReader { geometry in
            dropSubmitRoot(compactLayout: geometry.size.height < 780, geometry: geometry)
        }
        .navigationTitle("")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $viewModel.editorContext) { context in
            NavigationStack {
                WeeklyDropEditorView(
                    context: context,
                    persistsComposerDraft: {
                        if case .create = context.mode { return true }
                        return false
                    }(),
                    isWindowOpen: isWindowOpen,
                    slotsRemaining: slotsRemaining,
                    isSubmitting: viewModel.isSubmitting,
                    onSubmit: { draft in
                        try await viewModel.submitDraft(
                            draft,
                            mode: context.mode,
                            slotsRemaining: slotsRemaining,
                            isWindowOpen: isWindowOpen,
                            sellerPreviewMode: sellerPreviewMode,
                            sellerSubscription: sellerSubscription,
                            catalog: catalog.products
                        )
                        catalogRefreshToken += 1
                    }
                )
            }
            .overlay {
                if viewModel.isSubmitting {
                    ZStack {
                        Color.black.opacity(0.12)
                            .ignoresSafeArea()
                        AppOperationOverlay(
                            title: viewModel.submittingTitle,
                            subtitle: viewModel.submittingSubtitle
                        )
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.28), value: viewModel.isSubmitting)
        }
        .task {
            await reloadWorkspace()
            refreshSavedComposer()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshSavedComposer()
        }
        .confirmationDialog(
            "Continue your drop product?",
            isPresented: $isShowingDropComposerResumeDialog,
            titleVisibility: .visible
        ) {
            Button("Continue where I left off") {
                if let saved = savedWeeklyDropComposer {
                    viewModel.presentNewEditor(sellerId: sellerId, restored: saved)
                }
            }
            Button("Delete draft and start new", role: .destructive) {
                SellerProductComposerDraftStore.clearWeeklyDrop(sellerId: sellerId)
                refreshSavedComposer()
                viewModel.presentNewEditor(sellerId: sellerId)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have an unfinished Weekly Drop listing. Continue editing it, or delete the draft and start fresh.")
        }
    }

    @ViewBuilder
    private func dropSubmitRoot(compactLayout: Bool, geometry: GeometryProxy) -> some View {
        let hPad: CGFloat = compactLayout ? 14 : 18
        let lineupBottomInset = max(
            geometry.safeAreaInsets.bottom + (compactLayout ? 12 : 18),
            compactLayout ? 28 : 48
        )

        ZStack {
            VStack(spacing: 0) {
                if viewModel.isLoading && viewModel.submissions == nil {
                    WeeklyDropSkeletonStack()
                        .padding(.horizontal, hPad)
                        .padding(.top, compactLayout ? 8 : 14)
                    Spacer(minLength: 0)
                } else {
                    VStack(alignment: .leading, spacing: compactLayout ? 16 : 24) {
                        WeeklyDropHeroCard(
                            title: "This Week's Drop",
                            subtitle: statusSubtitle,
                            microLabel: statusMicroLabel,
                            slotsUsed: slotsUsed,
                            slotsMax: slotsMax,
                            supportiveText: statusSupportText,
                            countdownText: countdownText,
                            isWindowOpen: isWindowOpen,
                            compactLayout: compactLayout,
                            actionTitle: nil,
                            actionSubtitle: nil,
                            buttonTitle: nil,
                            showsBrandMark: hasDropAccess,
                            action: nil
                        )

                        if let feedback = viewModel.feedback {
                            WeeklyDropNoticeCard(
                                style: feedback.style,
                                title: feedback.title,
                                message: feedback.message,
                                actionTitle: nil,
                                action: nil
                            )
                        }

                        if let saved = savedWeeklyDropComposer,
                           saved.isCreateMode,
                           saved.draft.hasComposerProgress,
                           viewModel.editorContext == nil {
                            weeklyDropComposerResumeCard(saved)
                        }

                        lineupSectionHeader(compactLayout: compactLayout)
                        lineupActionControl(compactLayout: compactLayout)
                    }
                    .padding(.horizontal, hPad)
                    .padding(.top, compactLayout ? 8 : 14)

                    if viewModel.products.isEmpty {
                        Spacer(minLength: 0)
                    } else {
                        lineupList(
                            compactLayout: compactLayout,
                            hPad: hPad,
                            bottomInset: lineupBottomInset
                        )
                            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                            .layoutPriority(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(TBFrostBackground())

            if viewModel.isSubmitting && viewModel.editorContext == nil {
                AppOperationOverlay(
                    title: viewModel.submittingTitle,
                    subtitle: viewModel.submittingSubtitle
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(1)
            }
        }
    }

    /// Explicit closure so the main `body` type-checker does not choke on optional method references.
    private var heroCardAction: (() -> Void)? {
        guard heroButtonTitle != nil else { return nil }
        return {
            handleHeroAction()
        }
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                WeeklyDropMicroBadge(
                    title: "Seller Edition",
                    icon: "sparkles"
                )

                WeeklyDropMicroBadge(
                    title: isWindowOpen ? "Submission Window" : "Friday Release",
                    icon: isWindowOpen ? "clock.badge.checkmark" : "calendar.badge.clock"
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Weekly Drop")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .tracking(-0.9)
                    .foregroundStyle(TBTheme.deepSky.opacity(0.96))

                Text("Prepare a focused lineup for this Friday's featured release.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.56))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 10)
    }

    private func lineupSectionHeader(compactLayout: Bool) -> some View {
        HStack {
            Text("Current Lineup")
                .font(.system(size: compactLayout ? 17 : 18, weight: .semibold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky.opacity(0.94))

            Spacer()

            Text(viewModel.products.isEmpty
                 ? "No products yet"
                 : "\(viewModel.products.count) in lineup")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(TBTheme.icyBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.8))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
                )
        }
    }

    @ViewBuilder
    private func lineupActionControl(compactLayout: Bool) -> some View {
        if isWindowOpen && slotsRemaining > 0 {
            Button {
                handleAddDropProduct()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: compactLayout ? 16 : 18, weight: .semibold))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Drop Product")
                            .font(.system(size: compactLayout ? 15 : 16, weight: .semibold, design: .rounded))
                        Text(addProductActionSubtitle)
                            .font(.system(size: compactLayout ? 11 : 12, weight: .medium, design: .rounded))
                            .opacity(0.86)
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: compactLayout ? 13 : 14, weight: .semibold))
                }
            }
            .buttonStyle(WeeklyDropInlineActionButtonStyle(compactLayout: compactLayout))
            .accessibilityLabel("Add drop product")
        }
    }

    private var addProductActionSubtitle: String {
        "\(slotsRemaining) slot\(slotsRemaining == 1 ? "" : "s") available for this week's lineup"
    }

    private func lineupList(compactLayout: Bool, hPad: CGFloat, bottomInset: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: compactLayout ? 8 : 10) {
                ForEach(Array(viewModel.products.enumerated()), id: \.element.id) { index, product in
                    WeeklyDropSubmissionPill(
                        product: product,
                        status: WeeklyDropDisplayStatus(product: product, isDropLive: viewModel.isDropLive),
                        slotNumber: product.slotNumber ?? index + 1,
                        compactLayout: compactLayout,
                        canDelete: isWindowOpen,
                        onEdit: {
                            viewModel.presentEditor(for: product)
                        },
                        onDelete: {
                            Task {
                                await viewModel.deleteProduct(
                                    product,
                                    isWindowOpen: isWindowOpen,
                                    catalog: catalog.products
                                )
                                catalogRefreshToken += 1
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, hPad)
            .padding(.top, compactLayout ? 8 : 10)
            .padding(.bottom, bottomInset)
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        #if os(iOS)
        .scrollContentBackground(.hidden)
        #endif
    }

    private var heroActionTitle: String? {
        guard hasDropAccess else { return nil }
        guard shouldShowPrimaryActionCard else { return nil }
        return primaryCTATitle
    }

    private var heroActionSubtitle: String? {
        guard hasDropAccess else { return nil }
        guard shouldShowPrimaryActionCard else { return nil }
        return primaryCTASubtitle
    }

    private var heroButtonTitle: String? {
        guard hasDropAccess else { return nil }
        guard shouldShowPrimaryActionCard else { return nil }
        return primaryCTATitle
    }

    private func handleHeroAction() {
        if slotsRemaining > 0 {
            handleAddDropProduct()
        } else if let product = viewModel.products.first {
            viewModel.presentEditor(for: product)
        }
    }

    private func handleAddDropProduct() {
        refreshSavedComposer()
        if let saved = savedWeeklyDropComposer,
           saved.isCreateMode,
           saved.draft.hasComposerProgress {
            isShowingDropComposerResumeDialog = true
        } else {
            viewModel.presentNewEditor(sellerId: sellerId)
        }
    }

    private func refreshSavedComposer() {
        let trimmedSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSellerId.isEmpty else {
            savedWeeklyDropComposer = nil
            return
        }
        savedWeeklyDropComposer = SellerProductComposerDraftStore.loadWeeklyDrop(sellerId: trimmedSellerId)
    }

    private func weeklyDropComposerResumeCard(_ saved: WeeklyDropComposerDraft) -> some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TBTheme.icyBlue)

                    Text("Pick up where you left off")
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)
                }

                Text(
                    saved.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "You have an unfinished Weekly Drop product ready to keep editing."
                        : "Continue \"\(saved.draft.name)\" or delete the draft."
                )
                .font(.tbBody)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Continue") {
                        viewModel.presentNewEditor(sellerId: sellerId, restored: saved)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TBTheme.skyBlue)

                    Button("Delete draft", role: .destructive) {
                        SellerProductComposerDraftStore.clearWeeklyDrop(sellerId: sellerId)
                        refreshSavedComposer()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var primaryCTATitle: String {
        if slotsRemaining > 0 {
            return "Create Drop Product"
        }
        return "Review This Week's Drop"
    }

    private var primaryCTASubtitle: String {
        if slotsRemaining > 0 {
            return "Start a featured product reserved for Friday's release"
        }
        return "Fine-tune copy and shipping for this drop."
    }

    private var statusSubtitle: String {
        if isWindowOpen {
            return "Submissions stay open through Thursday night"
        }
        if !viewModel.products.isEmpty {
            return "Thursday uploads are closed. Existing drop products stay visible here for review before the release goes live."
        }
        if let next = viewModel.submissions?.nextDropAt {
            return "Submission access opens \(DropCountdown.timeLeft(until: next))"
        }
        return "Thursday uploads are closed right now. New submissions reopen during the next Thursday window."
    }

    private var statusSupportText: String {
        if isWindowOpen {
            if slotsRemaining == 0 {
                return "Your lineup is full. You can still edit products before the window closes tonight."
            }
            if !viewModel.products.isEmpty {
                return "Add or update before Thursday 11:59 PM ET."
            }
            if slotsRemaining == 1 {
                return "1 release slot is open for this week's lineup."
            }
            return "\(slotsRemaining) release slots are open for this week's lineup."
        }
        if viewModel.products.isEmpty {
            return "No new drop uploads are available right now."
        }
        return "Uploads are locked. New photos, videos, and submissions reopen on Thursday."
    }

    private var statusMicroLabel: String {
        isWindowOpen ? "Thursday submission window" : "This week's release"
    }

    private var countdownText: String? {
        if isWindowOpen {
            return "Closes tonight"
        }
        return viewModel.submissions?.nextDropAt.map { DropCountdown.timeLeft(until: $0) }
    }

    private func reloadWorkspace() async {
        await sellerSubscription.refresh()
        if usesPreviewData {
            return
        }
        await viewModel.loadSubmissions(sellerId: sellerId, catalog: catalog.products)
    }
}

@MainActor
private final class WeeklyDropPrepViewModel: ObservableObject {
    @Published var submissions: SellerSubmissionsResponse?
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var workspaceError: String?
    @Published var feedback: WeeklyDropFeedback?
    @Published var editorContext: WeeklyDropEditorContext?

    var products: [DropProduct] {
        submissions?.products ?? []
    }

    var isDropLive: Bool {
        submissions?.isActive == true
    }

    var submittingTitle: String {
        "Preparing Weekly Drop"
    }

    var submittingSubtitle: String {
        "Uploading media and saving your Friday release."
    }

    init(initialSubmissions: SellerSubmissionsResponse? = nil) {
        submissions = initialSubmissions
    }

    func loadSubmissions(sellerId: String, catalog: [RemoteProduct] = []) async {
        guard !sellerId.isEmpty else { return }
        isLoading = true
        if submissions == nil {
            workspaceError = nil
        }

        do {
            let resolvedSellerId = MarketplaceAuthSession.authenticatedSellerId() ?? sellerId
            let response = try await DropAPI.mySubmissions(sellerId: resolvedSellerId)
            submissions = Self.filteredSubmissions(response, catalog: catalog)
            workspaceError = nil
        } catch {
            workspaceError = "Please try again in a moment."
        }

        isLoading = false
    }

    private static func filteredSubmissions(
        _ response: SellerSubmissionsResponse,
        catalog: [RemoteProduct]
    ) -> SellerSubmissionsResponse {
        guard !catalog.isEmpty else { return response }
        let products = response.products.filter {
            CatalogSeedPolicy.isEnrolledWeeklyDropProduct(id: $0.id, catalog: catalog)
        }
        return SellerSubmissionsResponse(
            sellerId: response.sellerId,
            weekId: response.weekId,
            isActive: response.isActive,
            nextDropAt: response.nextDropAt,
            slotsUsed: products.count,
            slotsMax: response.slotsMax,
            products: products
        )
    }

    func presentNewEditor(
        sellerId: String,
        stage: WeeklyDropEditorStage = .basics,
        restored: WeeklyDropComposerDraft? = nil
    ) {
        if let restored {
            editorContext = WeeklyDropEditorContext(
                draft: restored.draft,
                mode: .create,
                stage: WeeklyDropEditorStage(rawValue: restored.stageRawValue) ?? stage
            )
            return
        }

        editorContext = WeeklyDropEditorContext(
            draft: WeeklyDropDraft.new(sellerId: sellerId),
            mode: .create,
            stage: stage
        )
    }

    func presentEditor(for product: DropProduct, stage: WeeklyDropEditorStage = .basics) {
        editorContext = WeeklyDropEditorContext(
            draft: WeeklyDropDraft(product: product),
            mode: .edit(productId: product.id),
            stage: stage
        )
    }

    func submitDraft(
        _ draft: WeeklyDropDraft,
        mode: WeeklyDropEditorMode,
        slotsRemaining: Int,
        isWindowOpen: Bool,
        sellerPreviewMode: Bool,
        sellerSubscription: SellerSubscriptionStore,
        catalog: [RemoteProduct] = []
    ) async throws {
        await sellerSubscription.refresh()

        guard draft.priceCents >= DropConstants.minPriceCents else {
            throw WeeklyDropEditorError.premiumPriceRequired
        }
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WeeklyDropEditorError.missingName
        }
        guard isWindowOpen else {
            throw WeeklyDropEditorError.windowClosed
        }
        guard draft.isReadyForSubmission else {
            throw WeeklyDropEditorError.incompleteDraft
        }
        if case .create = mode, slotsRemaining <= 0 {
            throw WeeklyDropEditorError.noSlotsRemaining
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let uploadedDraft = try await WeeklyDropSubmissionUploader.prepareDraftForSubmission(draft)
        let request = uploadedDraft.submissionRequest

        let savedProduct: DropProduct
        switch mode {
        case .create:
            savedProduct = try await DropAPI.submitProduct(request)
            feedback = WeeklyDropFeedback(
                style: .success,
                title: "Drop product submitted",
                message: "\(savedProduct.name) is ready for review."
            )
        case .edit(let productId):
            savedProduct = try await DropAPI.updateSubmission(productId: productId, request: request)
            feedback = WeeklyDropFeedback(
                style: .success,
                title: "Drop product updated",
                message: "\(savedProduct.name) has been refreshed for this week's release."
            )
        }

        await loadSubmissions(sellerId: draft.sellerId, catalog: catalog)
        SellerProductComposerDraftStore.clearWeeklyDrop(sellerId: draft.sellerId)
        editorContext = nil
    }

    func deleteProduct(_ product: DropProduct, isWindowOpen: Bool, catalog: [RemoteProduct] = []) async {
        guard isWindowOpen else {
            feedback = WeeklyDropFeedback(
                style: .error,
                title: "Deletion unavailable",
                message: "Drop submissions can only be removed during the Thursday upload window."
            )
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await DropAPI.deleteSubmission(productId: product.id)
            feedback = WeeklyDropFeedback(
                style: .info,
                title: "Drop product removed",
                message: "\(product.name) was removed from this week's lineup."
            )
            await loadSubmissions(sellerId: product.sellerId, catalog: catalog)
        } catch {
            feedback = WeeklyDropFeedback(
                style: .error,
                title: "We couldn't remove that product",
                message: error.localizedDescription
            )
        }
    }
}

private struct WeeklyDropEditorContext: Identifiable {
    let id = UUID()
    let draft: WeeklyDropDraft
    let mode: WeeklyDropEditorMode
    let stage: WeeklyDropEditorStage
}

private enum WeeklyDropEditorMode: Equatable {
    case create
    case edit(productId: String)

    var title: String {
        switch self {
        case .create:
            return "Create Weekly Drop"
        case .edit:
            return "Edit Drop Product"
        }
    }

    var submitTitle: String {
        switch self {
        case .create:
            return "Submit for Friday Review"
        case .edit:
            return "Submit"
        }
    }
}

private enum WeeklyDropEditorStage: Int, CaseIterable, Identifiable {
    case basics
    case story
    case media
    case review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .basics:
            return "Basics"
        case .story:
            return "Story"
        case .media:
            return "Media"
        case .review:
            return "Review"
        }
    }

    var subtitle: String {
        switch self {
        case .basics:
            return "Product details"
        case .story:
            return "Release narrative"
        case .media:
            return "Hero assets"
        case .review:
            return "Final pass"
        }
    }

    var icon: String {
        switch self {
        case .basics:
            return "tag.fill"
        case .story:
            return "sparkles.rectangle.stack.fill"
        case .media:
            return "photo.stack.fill"
        case .review:
            return "checkmark.seal.fill"
        }
    }
}

private struct WeeklyDropEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore

    let context: WeeklyDropEditorContext
    let persistsComposerDraft: Bool
    let isWindowOpen: Bool
    let slotsRemaining: Int
    let isSubmitting: Bool
    let onSubmit: (WeeklyDropDraft) async throws -> Void

    @State private var draft: WeeklyDropDraft
    @State private var stage: WeeklyDropEditorStage
    @State private var selectedImageItems: [PhotosPickerItem] = []
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedProductionPreviewItem: PhotosPickerItem?
    @State private var selectedVideoPlayer: AVPlayer?
    @State private var selectedProductionPreviewPlayer: AVPlayer?
    @State private var selectedVideoDurationSeconds: Double?
    @State private var selectedProductionPreviewDurationSeconds: Double?
    @State private var mediaErrorMessage: String?
    @State private var submissionErrorMessage: String?
    @State private var draggedImageURLString: String?

    /// Public creator clip (gallery): keep short for the featured drop.
    private let maxCreatorClipDurationSeconds: Double = 45
    /// Private maker / production preview: allow longer clips (at least 20s per product requirements).
    private let maxMakerVideoDurationSeconds: Double = 120

    init(
        context: WeeklyDropEditorContext,
        persistsComposerDraft: Bool = false,
        isWindowOpen: Bool,
        slotsRemaining: Int,
        isSubmitting: Bool,
        onSubmit: @escaping (WeeklyDropDraft) async throws -> Void
    ) {
        self.context = context
        self.persistsComposerDraft = persistsComposerDraft
        self.isWindowOpen = isWindowOpen
        self.slotsRemaining = slotsRemaining
        self.isSubmitting = isSubmitting
        self.onSubmit = onSubmit
        _draft = State(initialValue: context.draft)
        _stage = State(initialValue: context.stage)
    }

    private var canAdvance: Bool {
        switch stage {
        case .basics:
            return !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.priceCents > 0
        case .story:
            return !draft.story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .media:
            return !draft.imageURLStrings.isEmpty && creatorClipDurationValid && makerVideoDurationValid
        case .review:
            return draft.isReadyForSubmission && creatorClipDurationValid && makerVideoDurationValid
        }
    }

    private var creatorClipDurationValid: Bool {
        guard let selectedVideoDurationSeconds else { return true }
        return selectedVideoDurationSeconds <= maxCreatorClipDurationSeconds
    }

    /// Optional maker video: valid if absent, or duration within max when known.
    private var makerVideoDurationValid: Bool {
        guard !draft.productionPreviewURLString.isEmpty else { return true }
        guard let selectedProductionPreviewDurationSeconds else { return true }
        return selectedProductionPreviewDurationSeconds <= maxMakerVideoDurationSeconds
    }

    private var mediaEditingAllowed: Bool {
        isWindowOpen
    }

    private var composerAutosaveFingerprint: String {
        [
            draft.id,
            draft.name,
            draft.headline,
            draft.priceText,
            draft.story,
            draft.bestUseCase,
            draft.imageURLStrings.joined(separator: "|"),
            draft.demoVideoURLString,
            draft.productionPreviewURLString,
            draft.availableColors.map { "\($0.id):\($0.name):\($0.hex ?? "")" }.joined(separator: "|"),
            String(stage.rawValue),
        ].joined(separator: "§")
    }

    private func persistComposerDraftIfNeeded() {
        guard persistsComposerDraft else { return }
        guard case .create = context.mode else { return }
        SellerProductComposerDraftStore.saveWeeklyDrop(
            draft: draft,
            stageRawValue: stage.rawValue,
            isCreateMode: true
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                editorHeader
                stagePills

                if let submissionErrorMessage {
                    WeeklyDropNoticeCard(
                        style: .error,
                        title: "Your drop product needs one more pass",
                        message: submissionErrorMessage,
                        actionTitle: nil,
                        action: nil
                    )
                }

                switch stage {
                case .basics:
                    basicsStage
                case .story:
                    storyStage
                case .media:
                    mediaStage
                case .review:
                    reviewStage
                }

                stageFooter
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(TBFrostBackground())
        .navigationTitle(context.mode.title)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") {
                    persistComposerDraftIfNeeded()
                    dismiss()
                }
                .foregroundStyle(TBTheme.deepSky)
            }
        }
        .onChange(of: composerAutosaveFingerprint) { _, _ in
            persistComposerDraftIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background || phase == .inactive else { return }
            persistComposerDraftIfNeeded()
        }
        .onDisappear {
            persistComposerDraftIfNeeded()
        }
        .onChange(of: selectedImageItems) { _, items in
            Task { await loadSelectedImages(from: items) }
        }
        .onChange(of: selectedVideoItem) { _, item in
            Task { await loadSelectedVideo(from: item) }
        }
        .onChange(of: selectedProductionPreviewItem) { _, item in
            Task { await loadSelectedProductionPreview(from: item) }
        }
        .onChange(of: draft.demoVideoURLString) { _, newValue in
            updatePlayer(
                binding: &selectedVideoPlayer,
                urlString: newValue
            )
        }
        .onChange(of: draft.productionPreviewURLString) { _, newValue in
            updatePlayer(
                binding: &selectedProductionPreviewPlayer,
                urlString: newValue
            )
        }
        .allowsHitTesting(!isSubmitting)
    }

    private var editorHeader: some View {
        GlassCard(cornerRadius: 26, snowfallFlakeCount: 54) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    WeeklyDropMicroBadge(
                        title: context.mode == .create ? "Create Your Weekly Drop" : "Refine This Release",
                        icon: "sparkles"
                    )

                    if !isWindowOpen {
                        WeeklyDropMicroBadge(
                            title: "Uploads Closed",
                            icon: "calendar.badge.clock"
                        )
                    }
                }

                Text("This product will appear in the Friday featured drop instead of the standard everyday storefront.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
                    .fixedSize(horizontal: false, vertical: true)

                Text(editorHeaderSubtitle)
                    .font(.tbBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var editorHeaderSubtitle: String {
        if !isWindowOpen && context.mode != .create {
            return "Review this release here. New uploads, media changes, and resubmissions reopen during the next Thursday window."
        }
        return context.mode == .create
            ? "Build a more editorial listing, lead with stronger media, and review the full release card before submitting."
            : "Fine-tune this weekly release without leaving the dedicated drop workflow."
    }

    private var stagePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(WeeklyDropEditorStage.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            stage = item
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(item.title)
                                .font(.tbCaption)
                        }
                        .foregroundStyle(stage == item ? .white : TBTheme.deepSky)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Group {
                                if stage == item {
                                    Capsule().fill(TBTheme.dropBannerGradient)
                                } else {
                                    Capsule().fill(.white.opacity(0.82))
                                }
                            }
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(stage == item ? .white.opacity(0.14) : TBTheme.skyBlue.opacity(0.16), lineWidth: 0.9)
                        )
                        .shadow(color: stage == item ? TBTheme.deepSky.opacity(0.16) : .clear, radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var basicsStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            WeeklyDropEditorSectionCard(
                title: "Product Basics",
                subtitle: "Set the essentials for this featured Friday release."
            ) {
                WeeklyDropTextField(title: "Product title", text: $draft.name)
                WeeklyDropTextField(title: "Drop headline", text: $draft.headline)

                HStack(spacing: 12) {
                    WeeklyDropMenuField(
                        title: "Category",
                        selection: $draft.category
                    )

                    WeeklyDropPriceField(priceText: $draft.priceText)
                }

                if draft.priceCents > 0 && draft.priceCents < DropConstants.minPriceCents {
                    Text("Weekly Drop products must be priced above $10.00.")
                        .font(.tbCaption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var storyStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            WeeklyDropEditorSectionCard(
                title: "Product Story",
                subtitle: "Tell buyers why this release belongs in the drop."
            ) {
                WeeklyDropTextEditor(
                    title: "Why is this a drop item?",
                    text: $draft.story,
                    lineLimit: 4
                )

                WeeklyDropTextEditor(
                    title: "Best use case",
                    text: $draft.bestUseCase,
                    lineLimit: 3
                )
            }

            WeeklyDropEditorSectionCard(
                title: "Release Settings",
                subtitle: "Keep the supporting details launch-ready."
            ) {
                WeeklyDropTextField(title: "Material", text: $draft.material)
                ProductColorOptionsEditor(colors: $draft.availableColors)
                WeeklyDropTextEditor(
                    title: "Durability note",
                    text: $draft.durabilityNote,
                    lineLimit: 3
                )
                WeeklyDropTextEditor(
                    title: "Care warnings (one per line)",
                    text: $draft.careWarningsText,
                    lineLimit: 3
                )

                HStack(spacing: 12) {
                    WeeklyDropStepperCard(title: "Ships in min days", value: $draft.shipsInMinDays, range: 1...14)
                    WeeklyDropStepperCard(title: "Ships in max days", value: $draft.shipsInMaxDays, range: 1...21)
                }
            }
        }
    }

    private var mediaStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            WeeklyDropEditorSectionCard(
                title: "Featured Media",
                subtitle: "Lead with a strong hero image, then add supporting assets."
            ) {
                if !mediaEditingAllowed {
                    Text("Media uploads and removals close after Thursday night. You can still review the current media while editing the rest of this drop product.")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let mediaErrorMessage {
                    Text(mediaErrorMessage)
                        .font(.tbCaption)
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 10) {
                    PhotosPicker(
                        selection: $selectedImageItems,
                        maxSelectionCount: 5,
                        matching: .images
                    ) {
                        Label("Add Photos", systemImage: "photo.on.rectangle.angled")
                    }
                    .buttonStyle(SecondaryCTAButtonStyle())
                    .disabled(!mediaEditingAllowed)
                    .opacity(mediaEditingAllowed ? 1 : 0.55)

                    PhotosPicker(
                        selection: $selectedVideoItem,
                        matching: .videos
                    ) {
                        Label(draft.demoVideoURLString.isEmpty ? "Add Creator Clip" : "Replace Clip", systemImage: "video.badge.plus")
                    }
                    .buttonStyle(SecondaryCTAButtonStyle())
                    .disabled(!mediaEditingAllowed)
                    .opacity(mediaEditingAllowed ? 1 : 0.55)
                }

                if !draft.imageURLStrings.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(draft.imageURLStrings, id: \.self) { imageURLString in
                                weeklyDropImageThumbnail(for: imageURLString)
                            }
                        }
                    }
                }

                if !draft.demoVideoURLString.isEmpty {
                    weeklyDropVideoCard(
                        title: "Creator clip ready",
                        urlString: draft.demoVideoURLString,
                        player: selectedVideoPlayer,
                        canRemove: mediaEditingAllowed,
                        onRemove: {
                            draft.demoVideoURLString = ""
                            selectedVideoItem = nil
                            selectedVideoPlayer = nil
                            selectedVideoDurationSeconds = nil
                        }
                    )
                }

                if let selectedVideoDurationSeconds {
                    Text("Creator clip length: \(Int(selectedVideoDurationSeconds))s (max \(Int(maxCreatorClipDurationSeconds))s)")
                        .font(.tbCaption)
                        .foregroundStyle(creatorClipDurationValid ? Color.secondary : Color.orange)
                }

                PhotosPicker(
                    selection: $selectedProductionPreviewItem,
                    matching: .videos
                ) {
                    Label(
                        draft.productionPreviewURLString.isEmpty ? "Add Maker Video" : "Replace Maker Video",
                        systemImage: "sparkles.tv"
                    )
                }
                .buttonStyle(SecondaryCTAButtonStyle())
                .disabled(!mediaEditingAllowed)
                .opacity(mediaEditingAllowed ? 1 : 0.55)

                Text("Maker videos can run up to \(Int(maxMakerVideoDurationSeconds))s (20s+ supported).")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)

                if !draft.productionPreviewURLString.isEmpty {
                    weeklyDropVideoCard(
                        title: "Maker video ready",
                        urlString: draft.productionPreviewURLString,
                        player: selectedProductionPreviewPlayer,
                        canRemove: mediaEditingAllowed,
                        onRemove: {
                            draft.productionPreviewURLString = ""
                            selectedProductionPreviewItem = nil
                            selectedProductionPreviewPlayer = nil
                            selectedProductionPreviewDurationSeconds = nil
                        }
                    )
                }

                if let selectedProductionPreviewDurationSeconds {
                    Text("Maker video length: \(Int(selectedProductionPreviewDurationSeconds))s (max \(Int(maxMakerVideoDurationSeconds))s)")
                        .font(.tbCaption)
                        .foregroundStyle(makerVideoDurationValid ? Color.secondary : Color.orange)
                }
            }
        }
    }

    private var reviewStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            WeeklyDropEditorSectionCard(
                title: "Final Review",
                subtitle: "Preview the card and metadata before this release is sent for review."
            ) {
                HStack(alignment: .top, spacing: 14) {
                    StorefrontImageView(reference: draft.imageURLStrings.first) {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(TBTheme.heroGradient)
                            .overlay {
                                Image("Logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 42, height: 42)
                                    .opacity(0.92)
                            }
                    }
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.white.opacity(0.72), lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        WeeklyDropMicroBadge(title: "Friday Drop Preview", icon: "sparkles")

                        Text(draft.name.isEmpty ? "Untitled Drop Product" : draft.name)
                            .font(.tbCardTitle)
                            .foregroundStyle(TBTheme.deepSky)

                        if !draft.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(draft.headline)
                                .font(.tbBody)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Text(Money.format(cents: draft.priceCents))
                            .font(.tbProductPriceLG)
                            .foregroundStyle(TBTheme.icyBlue)
                    }
                }

                Divider()
                    .overlay(TBTheme.skyBlue.opacity(0.12))

                WeeklyDropReviewRow(label: "Story", value: draft.story)
                WeeklyDropReviewRow(label: "Best use", value: draft.bestUseCase)
                WeeklyDropReviewRow(label: "Material", value: draft.material)
                if !draft.availableColors.isEmpty {
                    WeeklyDropReviewRow(
                        label: "Colors",
                        value: draft.availableColors.map(\.name).joined(separator: ", ")
                    )
                }
                WeeklyDropReviewRow(label: "Ships", value: "\(min(draft.shipsInMinDays, draft.shipsInMaxDays))-\(max(draft.shipsInMinDays, draft.shipsInMaxDays)) days")
                WeeklyDropReviewRow(
                    label: "Media",
                    value: "\(draft.imageURLStrings.count) photo\(draft.imageURLStrings.count == 1 ? "" : "s")\(draft.demoVideoURLString.isEmpty ? "" : " + creator clip")\(draft.productionPreviewURLString.isEmpty ? "" : " + maker video")"
                )
            }

            ProductRightsOwnershipSection(
                ownershipType: $draft.rightsOwnershipType,
                referenceFlags: $draft.rightsReferenceFlags,
                certificationAccepted: $draft.rightsCertificationAccepted,
                certificationAcceptedAt: $draft.rightsCertificationAcceptedAt,
                showIncompleteMessage: !draft.isRightsConfirmationComplete
            )
        }
    }

    private var stageFooter: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    if let previousStage = previousStage {
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                stage = previousStage
                            }
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(WeeklyDropFooterButtonStyle(kind: .secondary))
                        .frame(maxWidth: .infinity)
                    }

                    if stage != .review {
                        Button {
                            guard let nextStage else { return }
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                stage = nextStage
                            }
                        } label: {
                            Label("Continue", systemImage: "chevron.right")
                        }
                        .buttonStyle(WeeklyDropFooterButtonStyle(kind: .primary))
                        .frame(maxWidth: .infinity)
                        .disabled(!canAdvance)
                    } else {
                        Button {
                            Task { await submit() }
                        } label: {
                            VStack(spacing: 4) {
                                Text(context.mode.submitTitle)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.8)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WeeklyDropLaunchButtonStyle(compactLayout: true))
                        .frame(maxWidth: .infinity, alignment: .top)
                        .disabled(!isWindowOpen || !canAdvance || isSubmitting)
                    }
                }

                Text(stageFooterCopy)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previousStage: WeeklyDropEditorStage? {
        WeeklyDropEditorStage(rawValue: stage.rawValue - 1)
    }

    private var nextStage: WeeklyDropEditorStage? {
        WeeklyDropEditorStage(rawValue: stage.rawValue + 1)
    }

    private var stageFooterCopy: String {
        switch stage {
        case .basics:
            return "Set the title, pricing, and category so the release has a strong foundation."
        case .story:
            return "Use the story section to make the release feel intentional and more editorial than a standard listing."
        case .media:
            return "Lead with polished media. Weekly Drop should feel like a featured Friday launch."
        case .review:
            if !isWindowOpen {
                return "Weekly Drop uploads are closed. You can review this release, but new submissions reopen Thursday evening."
            }
            return "Review the full release card and submit when everything feels polished."
        }
    }

    private func submit() async {
        submissionErrorMessage = nil
        mediaErrorMessage = nil

        do {
            if draft.rightsCertificationAccepted,
               draft.rightsCertificationAcceptedAt == nil {
                draft.rightsCertificationAcceptedAt = Date()
            }
            draft.refreshRightsReviewFlag()
            try await onSubmit(draft)
            dismiss()
        } catch {
            if let editorError = error as? WeeklyDropEditorError, case .membershipRequired = editorError {
                await sellerSubscription.refresh()
                await sellerSubscription.purchaseMembership()
            } else {
                submissionErrorMessage = error.localizedDescription
            }
        }
    }

    private func loadSelectedImages(from items: [PhotosPickerItem]) async {
        var loadedURLs: [String] = []
        for item in items.prefix(5) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpgData = image.jpegData(compressionQuality: 0.88),
                  let imageURL = WeeklyDropSubmissionUploader.writeTempFile(data: jpgData, fileExtension: "jpg")
            else {
                await MainActor.run {
                    mediaErrorMessage = "We couldn't load one of the selected images."
                }
                continue
            }
            loadedURLs.append(imageURL.absoluteString)
        }

        await MainActor.run {
            draft.imageURLStrings = loadedURLs
            draggedImageURLString = nil
            if !loadedURLs.isEmpty {
                mediaErrorMessage = nil
            }
        }
    }

    private func loadSelectedVideo(from item: PhotosPickerItem?) async {
        guard let item else {
            await MainActor.run {
                draft.demoVideoURLString = ""
                selectedVideoDurationSeconds = nil
            }
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let videoURL = WeeklyDropSubmissionUploader.writeTempFile(data: data, fileExtension: "mov")
            else {
                await MainActor.run {
                    mediaErrorMessage = "We couldn't load that video clip."
                }
                return
            }

            let durationSeconds = try await videoDurationSeconds(for: videoURL)

            await MainActor.run {
                draft.demoVideoURLString = videoURL.absoluteString
                selectedVideoDurationSeconds = durationSeconds
                mediaErrorMessage = durationSeconds > maxCreatorClipDurationSeconds
                    ? "Creator clips need to stay under \(Int(maxCreatorClipDurationSeconds)) seconds."
                    : nil
            }
        } catch {
            await MainActor.run {
                mediaErrorMessage = "We couldn't load that video clip."
            }
        }
    }

    private func loadSelectedProductionPreview(from item: PhotosPickerItem?) async {
        guard let item else {
            await MainActor.run {
                draft.productionPreviewURLString = ""
                selectedProductionPreviewDurationSeconds = nil
            }
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let videoURL = WeeklyDropSubmissionUploader.writeTempFile(data: data, fileExtension: "mov")
            else {
                await MainActor.run {
                    mediaErrorMessage = "We couldn't load that maker video."
                }
                return
            }

            let durationSeconds = try await videoDurationSeconds(for: videoURL)

            await MainActor.run {
                draft.productionPreviewURLString = videoURL.absoluteString
                selectedProductionPreviewDurationSeconds = durationSeconds
                mediaErrorMessage = durationSeconds > maxMakerVideoDurationSeconds
                    ? "Maker videos need to stay under \(Int(maxMakerVideoDurationSeconds)) seconds."
                    : nil
            }
        } catch {
            await MainActor.run {
                mediaErrorMessage = "We couldn't load that maker video."
            }
        }
    }

    private func weeklyDropImageThumbnail(for imageURLString: String) -> some View {
        ZStack(alignment: .topTrailing) {
            if let url = URL(string: imageURLString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(TBTheme.skyBlue.opacity(0.12))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 94, height: 94)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.72), lineWidth: 1)
                )
                .allowsHitTesting(mediaEditingAllowed)
                .onDrag {
                    draggedImageURLString = imageURLString
                    return NSItemProvider(object: imageURLString as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: DropMediaImageReorderDelegate(
                        item: imageURLString,
                        items: $draft.imageURLStrings,
                        draggedItem: $draggedImageURLString
                    )
                )
            }

            if mediaEditingAllowed {
                Button {
                    draft.imageURLStrings.removeAll { $0 == imageURLString }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white, .black.opacity(0.72))
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func weeklyDropVideoCard(
        title: String,
        urlString: String,
        player: AVPlayer?,
        canRemove: Bool,
        onRemove: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.tbBodyStrong)
                .foregroundStyle(TBTheme.deepSky)

            if let player {
                VideoPlayer(player: player)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.18), lineWidth: 1)
                    )
            }

            HStack {
                Text(URL(string: urlString)?.lastPathComponent ?? "Video ready")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if canRemove {
                    Button("Remove") {
                        onRemove()
                    }
                    .font(.tbCaption)
                    .foregroundStyle(.orange)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 0.8)
        )
    }

    private func updatePlayer(binding: inout AVPlayer?, urlString: String) {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            binding = nil
            return
        }

        if let existingPlayer = binding {
            existingPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        } else {
            binding = AVPlayer(url: url)
        }
    }

    private func videoDurationSeconds(for videoURL: URL) async throws -> Double {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        guard CMTIME_IS_NUMERIC(duration) else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? max(0, seconds) : 0
    }
}

private struct WeeklyDropHeroCard: View {
    let title: String
    let subtitle: String
    let microLabel: String
    let slotsUsed: Int
    let slotsMax: Int
    let supportiveText: String
    let countdownText: String?
    let isWindowOpen: Bool
    let compactLayout: Bool
    let actionTitle: String?
    let actionSubtitle: String?
    let buttonTitle: String?
    let showsBrandMark: Bool
    let action: (() -> Void)?

    var body: some View {
        let cornerRadius = compactLayout ? 24.0 : 28.0

        GlassCard(cornerRadius: cornerRadius, snowfallFlakeCount: compactLayout ? 36 : 64) {
            VStack(alignment: .leading, spacing: compactLayout ? 14 : 18) {
                HStack(alignment: .top, spacing: compactLayout ? 10 : 14) {
                    VStack(alignment: .leading, spacing: compactLayout ? 8 : 10) {
                        WeeklyDropMicroBadge(
                            title: microLabel,
                            icon: isWindowOpen ? "clock.badge.checkmark" : "sparkles",
                            compactLayout: compactLayout
                        )

                        Text(title)
                            .font(.system(size: compactLayout ? 19 : 22, weight: .bold, design: .rounded))
                            .tracking(-0.4)
                            .foregroundStyle(TBTheme.deepSky.opacity(0.94))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitle)
                            .font(.system(size: compactLayout ? 14 : 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.56))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    VStack(alignment: .trailing, spacing: compactLayout ? 8 : 10) {
                        if let countdownText {
                            Text(countdownText)
                                .font(.system(size: compactLayout ? 10 : 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(TBTheme.deepSky.opacity(0.82))
                                .padding(.horizontal, compactLayout ? 8 : 10)
                                .padding(.vertical, compactLayout ? 6 : 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(TBTheme.skyLight.opacity(0.38))
                                )
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(compactLayout ? "Slots" : "Slots filled")
                                .font(.system(size: compactLayout ? 10 : 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.primary.opacity(0.38))
                                .fixedSize(horizontal: true, vertical: false)

                            Text("\(slotsUsed) of \(slotsMax)")
                                .font(.system(size: compactLayout ? 22 : 26, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(TBTheme.icyBlue)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
                }

                VStack(alignment: .leading, spacing: compactLayout ? 10 : 14) {
                    HStack(spacing: compactLayout ? 8 : 12) {
                        ForEach(0..<slotsMax, id: \.self) { index in
                            Capsule()
                                .fill(index < slotsUsed ? LinearGradient(
                                    colors: [TBTheme.icyBlue.opacity(0.9), TBTheme.deepSky.opacity(0.92)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ) : LinearGradient(
                                    colors: [TBTheme.skyLight.opacity(0.45), Color.white.opacity(0.78)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(maxWidth: .infinity)
                                .frame(height: compactLayout ? 8 : 10)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(index < slotsUsed ? Color.white.opacity(0.42) : TBTheme.skyBlue.opacity(0.08), lineWidth: 0.6)
                                )
                        }
                    }

                    Text(supportiveText)
                        .font(.system(size: compactLayout ? 14 : 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.52))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let actionTitle, let actionSubtitle, let buttonTitle, let action {
                    Divider()
                        .overlay(TBTheme.skyBlue.opacity(0.12))

                    HStack(alignment: .center, spacing: compactLayout ? 10 : 14) {
                        heroLeadingMark

                        VStack(alignment: .leading, spacing: compactLayout ? 3 : 5) {
                            Text(actionTitle)
                                .font(.system(size: compactLayout ? 16 : 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(TBTheme.deepSky.opacity(0.95))

                            Text(actionSubtitle)
                                .font(.system(size: compactLayout ? 13 : 15, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.primary.opacity(0.52))
                                .lineSpacing(2)
                                .lineLimit(compactLayout ? 2 : 3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: action) {
                        HStack(spacing: 10) {
                            Text(buttonTitle)
                                .font(.system(size: compactLayout ? 16 : 17, weight: .semibold, design: .rounded))
                            Image(systemName: "arrow.right")
                                .font(.system(size: compactLayout ? 14 : 16, weight: .semibold))
                        }
                    }
                    .buttonStyle(WeeklyDropLaunchButtonStyle(compactLayout: compactLayout))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.16), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    private var heroLeadingMark: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [TBTheme.skyLight.opacity(0.78), TBTheme.skyBlue.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: compactLayout ? 48 : 60, height: compactLayout ? 48 : 60)
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                )

            if showsBrandMark {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: compactLayout ? 28 : 36, height: compactLayout ? 28 : 36)
                    .opacity(0.92)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: compactLayout ? 18 : 22, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky.opacity(0.9))
            }
        }
    }
}

private struct WeeklyDropPrimaryActionCard: View {
    let title: String
    let subtitle: String
    let compactLayout: Bool
    let action: () -> Void

    var body: some View {
        let cornerRadius = compactLayout ? 24.0 : 28.0

        GlassCard(cornerRadius: cornerRadius) {
            VStack(alignment: .leading, spacing: compactLayout ? 12 : 18) {
                HStack(alignment: .center, spacing: compactLayout ? 10 : 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [TBTheme.skyLight.opacity(0.78), TBTheme.skyBlue.opacity(0.28)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: compactLayout ? 48 : 60, height: compactLayout ? 48 : 60)
                            .overlay(
                                Circle()
                                    .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                            )
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: compactLayout ? 28 : 36, height: compactLayout ? 28 : 36)
                            .opacity(0.92)
                    }

                    VStack(alignment: .leading, spacing: compactLayout ? 3 : 5) {
                        Text(title)
                            .font(.system(size: compactLayout ? 16 : 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(TBTheme.deepSky.opacity(0.95))

                        Text(subtitle)
                            .font(.system(size: compactLayout ? 13 : 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.52))
                            .lineSpacing(2)
                            .lineLimit(compactLayout ? 2 : 3)
                    }
                }

                Button(action: action) {
                    HStack(spacing: 10) {
                        Text(title)
                            .font(.system(size: compactLayout ? 16 : 17, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: compactLayout ? 14 : 16, weight: .semibold))
                    }
                }
                .buttonStyle(WeeklyDropLaunchButtonStyle(compactLayout: compactLayout))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.14), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .allowsHitTesting(false)
        )
    }
}

private struct WeeklyDropSubmissionPill: View {
    let product: DropProduct
    let status: WeeklyDropDisplayStatus
    let slotNumber: Int
    let compactLayout: Bool
    let canDelete: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var swipeOffset: CGFloat = 0

    private var shipsRangeShort: String {
        let lo = min(product.shipsInMinDays, product.shipsInMaxDays)
        let hi = max(product.shipsInMinDays, product.shipsInMaxDays)
        if lo == hi { return "\(lo)d" }
        return "\(lo)–\(hi)d"
    }

    var body: some View {
        let rowCornerRadius: CGFloat = 20
        let imageCornerRadius: CGFloat = TBTheme.radiusMD
        let thumb: CGFloat = 64

        ZStack(alignment: .trailing) {
            if canDelete {
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .fill(Color.red.opacity(0.14))
                    .overlay(alignment: .trailing) {
                        Button(role: .destructive, action: onDelete) {
                            Label("Remove", systemImage: "trash")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.red.opacity(0.9))
                        .padding(.trailing, 12)
                    }
            }

            HStack(spacing: 10) {
                StorefrontImageView(reference: product.primaryImageReference) {
                    RoundedRectangle(cornerRadius: imageCornerRadius)
                        .fill(TBTheme.heroGradient)
                        .overlay {
                            Image(systemName: "cube.fill")
                                .font(.title2)
                                .foregroundStyle(TBTheme.skyBlue)
                        }
                }
                .frame(width: thumb, height: thumb)
                .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        WeeklyDropStatusChip(status: status, compactLayout: true)

                        Text("Slot \(slotNumber)")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(TBTheme.deepSky)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.92), in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
                            )
                    }

                    Text(product.name)
                        .font(.tbProductTitleSM)
                        .tbProductNameTitleStyle()
                        .lineLimit(2)

                    Text(product.displayHeadline)
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Money.format(cents: product.priceCents))
                            .font(.tbProductPriceSM)
                            .foregroundStyle(.primary.opacity(0.82))

                        Text("\(product.material) · \(shipsRangeShort)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer(minLength: 8)

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TBTheme.deepSky)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.92), in: Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(TBTheme.skyBlue.opacity(0.18), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(product.name)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: TBTheme.deepSky.opacity(0.08), radius: 10, y: 4)
            .offset(x: swipeOffset)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard canDelete else { return }
                        swipeOffset = min(0, max(-92, value.translation.width))
                    }
                    .onEnded { value in
                        guard canDelete else {
                            swipeOffset = 0
                            return
                        }

                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                            swipeOffset = value.translation.width < -44 ? -92 : 0
                        }
                    }
            )
            .onTapGesture {
                if swipeOffset != 0 {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        swipeOffset = 0
                    }
                }
            }
        }
    }
}

private struct WeeklyDropSkeletonStack: View {
    var body: some View {
        VStack(spacing: 14) {
            WeeklyDropSkeletonCard(height: 214)
            WeeklyDropSkeletonCard(height: 156)
            WeeklyDropSkeletonCard(height: 108)
            WeeklyDropSkeletonCard(height: 108)
        }
    }
}

private struct WeeklyDropSkeletonCard: View {
    let height: CGFloat
    @State private var shimmerOffset: CGFloat = -220

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0.82),
                        TBTheme.skyLight.opacity(0.44)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: height)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0),
                                .white.opacity(0.55),
                                .white.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(12))
                    .offset(x: shimmerOffset)
                    .mask(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.08), lineWidth: 0.8)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                    shimmerOffset = 260
                }
            }
    }
}

private struct WeeklyDropNoticeCard: View {
    let style: WeeklyDropNoticeStyle
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: style.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(style.tint)

                    Text(title)
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)
                }

                Text(message)
                    .font(.tbBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(SecondaryCTAButtonStyle())
                }
            }
        }
    }
}

private struct WeeklyDropLaunchButtonStyle: ButtonStyle {
    var compactLayout: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compactLayout ? 16 : 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: compactLayout ? 48 : 56)
            .padding(.horizontal, compactLayout ? 14 : 18)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: compactLayout ? 18 : 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                TBTheme.skyBlue.opacity(0.96),
                                TBTheme.accent.opacity(0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: compactLayout ? 18 : 20, style: .continuous)
                            .strokeBorder(.white.opacity(0.24), lineWidth: 0.9)
                    )
            )
            .shadow(color: TBTheme.deepSky.opacity(0.1), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private enum WeeklyDropFooterButtonKind {
    case primary
    case secondary
}

private struct WeeklyDropFooterButtonStyle: ButtonStyle {
    let kind: WeeklyDropFooterButtonKind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(kind == .primary ? .white : TBTheme.deepSky)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(backgroundFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
            .shadow(color: shadowColor, radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }

    private var backgroundFill: LinearGradient {
        switch kind {
        case .primary:
            return LinearGradient(
                colors: [TBTheme.skyBlue.opacity(0.96), TBTheme.accent.opacity(0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            return LinearGradient(
                colors: [Color.white.opacity(0.92), TBTheme.skyLight.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        kind == .primary ? .white.opacity(0.24) : TBTheme.skyBlue.opacity(0.20)
    }

    private var shadowColor: Color {
        kind == .primary ? TBTheme.deepSky.opacity(0.10) : TBTheme.deepSky.opacity(0.04)
    }
}

private struct WeeklyDropInlineActionButtonStyle: ButtonStyle {
    let compactLayout: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .font(.system(size: compactLayout ? 14 : 15, weight: .semibold, design: .rounded))
            .foregroundStyle(TBTheme.deepSky)
            .padding(.horizontal, compactLayout ? 14 : 18)
            .padding(.vertical, compactLayout ? 10 : 12)
            .frame(maxWidth: .infinity, minHeight: compactLayout ? 42 : 46)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: compactLayout ? 12 : 14))
            .overlay(
                RoundedRectangle(cornerRadius: compactLayout ? 12 : 14)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: TBTheme.deepSky.opacity(0.04), radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}

private enum WeeklyDropLineupActionKind {
    case edit
    case remove
}

private struct WeeklyDropLineupActionButtonStyle: ButtonStyle {
    let kind: WeeklyDropLineupActionKind
    let compactLayout: Bool

    func makeBody(configuration: Configuration) -> some View {
        let corner: CGFloat = 12
        let verticalPad: CGFloat = compactLayout ? 6 : 7
        let horizontalPad: CGFloat = compactLayout ? 8 : 10
        let minH: CGFloat = compactLayout ? 32 : 34

        let styledLabel = configuration.label
            .font(.system(size: compactLayout ? 12 : 13, weight: .semibold, design: .rounded))
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, minHeight: minH)
            .padding(.horizontal, horizontalPad)
            .padding(.vertical, verticalPad)
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.22), value: configuration.isPressed)

        Group {
            switch kind {
            case .edit:
                styledLabel
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [TBTheme.skyBlue.opacity(0.95), TBTheme.accent.opacity(0.92)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                    )
                    .shadow(color: TBTheme.deepSky.opacity(configuration.isPressed ? 0.06 : 0.14), radius: configuration.isPressed ? 2 : 6, y: 2)
            case .remove:
                styledLabel
                    .foregroundStyle(Color.red.opacity(0.92))
                    .background(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(Color.white.opacity(0.92))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: Color.red.opacity(0.08), radius: 4, y: 2)
            }
        }
    }
}

private enum WeeklyDropNoticeStyle {
    case info
    case success
    case error

    var icon: String {
        switch self {
        case .info:
            return "sparkles"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .info:
            return TBTheme.icyBlue
        case .success:
            return .green
        case .error:
            return .orange
        }
    }
}

private struct WeeklyDropFeedback {
    let style: WeeklyDropNoticeStyle
    let title: String
    let message: String
}

private struct WeeklyDropMicroBadge: View {
    let title: String
    let icon: String
    var compactLayout: Bool = false

    var body: some View {
        HStack(spacing: compactLayout ? 5 : 7) {
            Image(systemName: icon)
                .font(.system(size: compactLayout ? 9 : 10, weight: .semibold))
            Text(title)
                .font(.system(size: compactLayout ? 11 : 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(TBTheme.deepSky.opacity(0.9))
        .padding(.horizontal, compactLayout ? 10 : 12)
        .padding(.vertical, compactLayout ? 6 : 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.76))
        )
        .overlay(
            Capsule()
                .strokeBorder(TBTheme.skyBlue.opacity(0.1), lineWidth: 0.8)
        )
    }
}

private struct WeeklyDropStatusChip: View {
    let status: WeeklyDropDisplayStatus
    var compactLayout: Bool = false

    var body: some View {
        HStack(spacing: compactLayout ? 4 : 6) {
            Image(systemName: status.icon)
                .font(.system(size: compactLayout ? 8 : 10, weight: .semibold))
            Text(status.title)
                .font(.system(size: compactLayout ? 9 : 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(status.tint)
        .padding(.horizontal, compactLayout ? 6 : 10)
        .padding(.vertical, compactLayout ? 3 : 6)
        .background(status.background, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(status.tint.opacity(0.16), lineWidth: 0.7)
        )
    }
}

private enum WeeklyDropDisplayStatus: Equatable {
    case underReview
    case scheduled
    case live
    case needsChanges
    case archived

    init(product: DropProduct, isDropLive: Bool) {
        switch product.approvalStatus {
        case .approved:
            self = isDropLive ? .live : .scheduled
        case .rejected:
            self = .needsChanges
        case .archived:
            self = .archived
        case .live:
            self = .live
        case .draft, .ready, .submitted:
            self = isDropLive ? .live : .underReview
        }
    }

    var title: String {
        switch self {
        case .underReview:
            return "Under Review"
        case .scheduled:
            return "Scheduled"
        case .live:
            return "Live in Drop"
        case .needsChanges:
            return "Needs Changes"
        case .archived:
            return "Archived"
        }
    }

    var icon: String {
        switch self {
        case .underReview:
            return "clock.fill"
        case .scheduled:
            return "calendar.badge.checkmark"
        case .live:
            return "sparkles"
        case .needsChanges:
            return "exclamationmark.triangle.fill"
        case .archived:
            return "tray.full.fill"
        }
    }

    var tint: Color {
        switch self {
        case .underReview:
            return TBTheme.icyBlue
        case .scheduled:
            return TBTheme.deepSky
        case .live:
            return .green
        case .needsChanges:
            return .orange
        case .archived:
            return .secondary
        }
    }

    var background: Color {
        switch self {
        case .underReview:
            return TBTheme.skyBlue.opacity(0.12)
        case .scheduled:
            return TBTheme.skyLight.opacity(0.4)
        case .live:
            return Color.green.opacity(0.14)
        case .needsChanges:
            return Color.orange.opacity(0.12)
        case .archived:
            return Color.gray.opacity(0.12)
        }
    }
}

private struct WeeklyDropMetaPill: View {
    let text: String
    var lineupDense: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: lineupDense ? 9 : 12, weight: .semibold, design: .rounded))
            .foregroundStyle(TBTheme.deepSky)
            .padding(.horizontal, lineupDense ? 7 : 10)
            .padding(.vertical, lineupDense ? 3 : 6)
            .background(TBTheme.skyLight.opacity(0.34), in: Capsule())
            .lineLimit(1)
    }
}

private struct WeeklyDropEditorSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        GlassCard(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.tbCardTitle)
                        .foregroundStyle(TBTheme.deepSky)
                    Text(subtitle)
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content
            }
        }
    }
}

private struct WeeklyDropTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.plain)
            .font(.tbBody)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
            )
    }
}

private struct WeeklyDropTextEditor: View {
    let title: String
    @Binding var text: String
    let lineLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.tbBodyStrong)
                .foregroundStyle(TBTheme.deepSky)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.82))

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)

                if text.isEmpty {
                    Text(title)
                        .font(.tbBody)
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }

                TextEditor(text: $text)
                    .font(.tbBody)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: CGFloat(max(lineLimit, 3)) * 26)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.clear)
            }
        }
    }
}

private struct WeeklyDropMenuField: View {
    let title: String
    @Binding var selection: Category

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.tbBodyStrong)
                .foregroundStyle(TBTheme.deepSky)

            Picker(title, selection: $selection) {
                ForEach(Category.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WeeklyDropPriceField: View {
    @Binding var priceText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Price")
                .font(.tbBodyStrong)
                .foregroundStyle(TBTheme.deepSky)

            HStack(spacing: 10) {
                Text("$")
                    .font(.headline)
                    .foregroundStyle(TBTheme.icyBlue)
                    .padding(.leading, 14)

                TextField("15.00", text: $priceText)
                    .textFieldStyle(.plain)
                    .font(.tbBody)
                    .keyboardType(.decimalPad)
                    .padding(.trailing, 14)
            }
            .padding(.vertical, 14)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WeeklyDropStepperCard: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.tbBodyStrong)
                .foregroundStyle(TBTheme.deepSky)

            Stepper(value: $value, in: range) {
                Text("\(value)")
                    .font(.tbBody)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WeeklyDropReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.tbCaption)
                .foregroundStyle(.secondary)

            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not added yet" : value)
                .font(.tbBodyStrong)
                .foregroundStyle(TBTheme.deepSky)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum WeeklyDropEditorError: LocalizedError {
    case membershipRequired
    case windowClosed
    case noSlotsRemaining
    case premiumPriceRequired
    case missingName
    case incompleteDraft

    var errorDescription: String? {
        switch self {
        case .membershipRequired:
            return "Activate seller membership before submitting Weekly Drop products."
        case .windowClosed:
            return "Weekly Drop submissions open Thursday from 5:00 PM to 11:59 PM ET."
        case .noSlotsRemaining:
            return "All Weekly Drop slots are filled for this week."
        case .premiumPriceRequired:
            return "Weekly Drop products must be priced above $10.00."
        case .missingName:
            return "Add a product title before submitting."
        case .incompleteDraft:
            return "Finish the title, story, material, hero media, and pricing before submitting."
        }
    }
}

private enum WeeklyDropSubmissionUploader {
    static func prepareDraftForSubmission(_ draft: WeeklyDropDraft) async throws -> WeeklyDropDraft {
        var prepared = draft
        prepared.imageURLStrings = try await uploadImagesIfNeeded(prepared.imageURLStrings, sellerId: draft.sellerId, productId: draft.id)
        prepared.demoVideoURLString = try await uploadVideoIfNeeded(
            draft.demoVideoURLString,
            sellerId: draft.sellerId,
            productId: draft.id,
            mediaKind: "video"
        )
        prepared.productionPreviewURLString = try await uploadVideoIfNeeded(
            draft.productionPreviewURLString,
            sellerId: draft.sellerId,
            productId: draft.id,
            mediaKind: "production-preview"
        )
        return prepared
    }

    private static func uploadImagesIfNeeded(
        _ references: [String],
        sellerId: String,
        productId: String
    ) async throws -> [String] {
        var uploadedURLs: [String] = []

        for (index, reference) in references.enumerated() {
            if Product.mediaURL(for: reference) != nil {
                uploadedURLs.append(reference)
                continue
            }

            guard let fileURL = URL(string: reference), fileURL.isFileURL else {
                throw NSError(
                    domain: "WeeklyDropSubmissionUploader",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "One of the selected photos could not be prepared."]
                )
            }

            let data = try Data(contentsOf: fileURL)
            let fileExtension = fileURL.pathExtension.lowercased().isEmpty ? "jpg" : fileURL.pathExtension.lowercased()
            let uploadedURL = try await SellerAPI.uploadMedia(
                sellerId: sellerId,
                productId: productId,
                mediaKind: "image",
                slot: "\(index)",
                fileExtension: fileExtension,
                contentType: imageContentType(for: fileExtension),
                data: data
            )
            uploadedURLs.append(uploadedURL)
        }

        return uploadedURLs
    }

    private static func uploadVideoIfNeeded(
        _ reference: String,
        sellerId: String,
        productId: String,
        mediaKind: String
    ) async throws -> String {
        guard !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

        if Product.mediaURL(for: reference) != nil {
            return reference
        }

        guard let fileURL = URL(string: reference), fileURL.isFileURL else {
            throw NSError(
                domain: "WeeklyDropSubmissionUploader",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "One of the selected video files could not be prepared."]
            )
        }

        let data = try Data(contentsOf: fileURL)
        let fileExtension = fileURL.pathExtension.lowercased().isEmpty ? "mov" : fileURL.pathExtension.lowercased()
        return try await SellerAPI.uploadMedia(
            sellerId: sellerId,
            productId: productId,
            mediaKind: mediaKind,
            slot: "0",
            fileExtension: fileExtension,
            contentType: videoContentType(for: fileExtension),
            data: data
        )
    }

    static func writeTempFile(data: Data, fileExtension: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func imageContentType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        default:
            return "image/jpeg"
        }
    }

    private static func videoContentType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "webm":
            return "video/webm"
        default:
            return "application/octet-stream"
        }
    }
}

private struct DropMediaImageReorderDelegate: DropDelegate {
    let item: String
    @Binding var items: [String]
    @Binding var draggedItem: String?

    func dropEntered(info: DropInfo) {
        guard let draggedItem, draggedItem != item else { return }
        guard let fromIndex = items.firstIndex(of: draggedItem),
              let toIndex = items.firstIndex(of: item)
        else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            let target = toIndex > fromIndex ? toIndex + 1 : toIndex
            items.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: target)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
}

