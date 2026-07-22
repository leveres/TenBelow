import SwiftUI
import PhotosUI
import AVKit
#if os(iOS)
import UIKit
#endif

struct AddProductView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore

    let title: String
    let onSave: (SellerProductDraft, SellerProductMediaSelection) -> Void

    @State private var draft: SellerProductDraft
    @State private var selectedImageItems: [PhotosPickerItem] = []
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedProductionPreviewItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var selectedProductionPreviewURL: URL?
    @State private var isShowingVideoPreview = false
    @State private var isShowingProductionPreview = false
    @State private var mediaErrorMessage: String?
    @State private var isLoadingPhotos = false
    @State private var loadingPhotoPlaceholderCount = 0
    @State private var isLoadingCreatorClip = false
    @State private var isLoadingProductionPreview = false
    @State private var showRightsValidationMessage = false

    init(
        title: String = "Add Product",
        initialDraft: SellerProductDraft = .new(),
        onSave: @escaping (SellerProductDraft, SellerProductMediaSelection) -> Void = { _, _ in }
    ) {
        self.title = title
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    private let premiumListingThresholdCents = DropConstants.minPriceCents

    private var storefrontProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
    }

    private var currentSellerProfile: SellerProfile? {
        resolvedSellerProfile(
            sellerId: draft.sellerId,
            storefrontProducts: storefrontProducts.filter { $0.sellerId == draft.sellerId },
            remoteProfiles: catalog.sellerProfiles
        )
    }

    private var isPremiumListing: Bool {
        draft.priceCents >= premiumListingThresholdCents
    }

    private var canListPremiumProduct: Bool {
        currentSellerProfile?.showsVerifiedBadge == true
    }

    private var premiumListingBlocked: Bool {
        isPremiumListing && !canListPremiumProduct
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draft.priceCents > 0 &&
        !draft.material.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.productionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.durabilityNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.warningLines.isEmpty &&
        draft.shipsInMaxDays >= draft.shipsInMinDays &&
        !premiumListingBlocked &&
        draft.isRightsConfirmationComplete
    }

    private var remainingPhotoSlots: Int {
        max(0, 6 - draft.imageURLStrings.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TBTheme.spacingXL) {
                headerSection
                basicInfoSection
                detailsSection
                mediaSection
                productRightsOwnershipSection
                saveSection
            }
            .padding(TBTheme.spacingLG)
        }
        .background(TBFrostBackground())
        .navigationTitle(title)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if selectedVideoURL == nil,
               let url = URL(string: draft.demoVideoURLString),
               !draft.demoVideoURLString.isEmpty {
                selectedVideoURL = url
            }
            if selectedProductionPreviewURL == nil,
               let url = URL(string: draft.productionPreviewURLString),
               !draft.productionPreviewURLString.isEmpty {
                selectedProductionPreviewURL = url
            }
        }
        .onChange(of: selectedImageItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadSelectedImages(from: items) }
        }
        .onChange(of: selectedVideoItem) { _, item in
            Task { await loadSelectedVideo(from: item) }
        }
        .onChange(of: selectedProductionPreviewItem) { _, item in
            Task { await loadSelectedProductionPreview(from: item) }
        }
        .sheet(isPresented: $isShowingVideoPreview) {
            if let selectedVideoURL {
                AutoplayVideoPreview(url: selectedVideoURL)
            }
        }
        .sheet(isPresented: $isShowingProductionPreview) {
            if let selectedProductionPreviewURL {
                AutoplayVideoPreview(url: selectedProductionPreviewURL)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit product details")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)

            Text("Update title, price, shipping, and media in one place.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
    }

    private var basicInfoSection: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                Text("Product Basics")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                sellerFormField("Product name", text: $draft.name)

                sellerFormField("Price", text: $draft.priceText)
                    .keyboardType(.decimalPad)

                if premiumListingBlocked {
                    Text("Prices of \(Money.format(cents: premiumListingThresholdCents)) and above require seller verification. Lower the price to \(Money.format(cents: premiumListingThresholdCents - 1)) or below to submit now.")
                        .font(.tbCaption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isPremiumListing {
                    Text("Verified seller pricing unlocked.")
                        .font(.tbCaption)
                        .foregroundStyle(.green)
                }

                Picker("Category", selection: $draft.category) {
                    ForEach(Category.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
                )
            }
        }
    }

    private var detailsSection: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                Text("Detail Page Content")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                sellerFormField("Material", text: $draft.material)

                sellerFormField("Status note", text: $draft.productionNote)

                sellerTextEditor(
                    title: "Durability note",
                    text: $draft.durabilityNote,
                    lineLimit: 3
                )

                sellerTextEditor(
                    title: "Care warnings (one per line)",
                    text: $draft.careWarningsText,
                    lineLimit: 4
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Shipping window")
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)

                    HStack(spacing: 12) {
                        sellerStepperCard(title: "Min days", value: $draft.shipsInMinDays, range: 1...14)
                        sellerStepperCard(title: "Max days", value: $draft.shipsInMaxDays, range: 1...21)
                    }
                }
            }
        }
    }

    private var mediaSection: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                Text("Product Media")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                Text("Add up to 6 photos, one public creator clip, and one private maker video for orders.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                if let mediaErrorMessage {
                    Text(mediaErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                PhotosPicker(
                    selection: $selectedImageItems,
                    maxSelectionCount: max(remainingPhotoSlots, 1),
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    mediaPickerButtonLabel(
                        title: isLoadingPhotos
                            ? "Adding Photos..."
                            : (draft.imageURLStrings.isEmpty ? "Add Photos" : "Add More Photos"),
                        icon: "photo.on.rectangle.angled",
                        isProcessing: isLoadingPhotos
                    )
                }
                .buttonStyle(.plain)
                .disabled(remainingPhotoSlots == 0 || isLoadingPhotos)
                .opacity(remainingPhotoSlots == 0 ? 0.6 : 1)

                if !draft.imageURLStrings.isEmpty || isLoadingPhotos {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(draft.imageURLStrings.enumerated()), id: \.offset) { index, reference in
                                productPhotoThumbnail(reference: reference, index: index)
                            }
                            ForEach(0..<loadingPhotoPlaceholderCount, id: \.self) { _ in
                                productPhotoLoadingThumbnail
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(height: 114)
                    .transition(.opacity)
                }

                PhotosPicker(
                    selection: $selectedVideoItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    mediaPickerButtonLabel(
                        title: isLoadingCreatorClip
                            ? "Loading Creator Clip..."
                            : (selectedVideoURL == nil ? "Add Creator Clip" : "Replace Creator Clip"),
                        icon: "video.badge.plus",
                        isAttached: selectedVideoURL != nil,
                        isProcessing: isLoadingCreatorClip
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoadingCreatorClip)

                if isLoadingCreatorClip || selectedVideoURL != nil {
                    mediaAttachmentRow(
                        title: isLoadingCreatorClip ? "Preparing creator clip" : "Creator clip ready",
                        fileName: selectedVideoURL?.lastPathComponent ?? "Importing video...",
                        icon: "video.fill",
                        isProcessing: isLoadingCreatorClip,
                        previewAction: { isShowingVideoPreview = true },
                        removeAction: clearSelectedVideo
                    )
                    .transition(.opacity)
                }

                Divider()
                    .overlay(TBTheme.skyBlue.opacity(0.10))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Maker Video (Orders only)")
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)

                    Text("Optional private clip shown in the buyer's \"see your item being made\" section after production begins. Not visible in the public gallery.")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PhotosPicker(
                    selection: $selectedProductionPreviewItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    mediaPickerButtonLabel(
                        title: isLoadingProductionPreview
                            ? "Loading Maker Video..."
                            : (selectedProductionPreviewURL == nil ? "Add Maker Video" : "Replace Maker Video"),
                        icon: "sparkles.tv",
                        isAttached: selectedProductionPreviewURL != nil,
                        isProcessing: isLoadingProductionPreview
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoadingProductionPreview)

                if isLoadingProductionPreview || selectedProductionPreviewURL != nil {
                    mediaAttachmentRow(
                        title: isLoadingProductionPreview ? "Preparing maker video" : "Maker video ready",
                        fileName: selectedProductionPreviewURL?.lastPathComponent ?? "Importing video...",
                        icon: "sparkles.tv",
                        isProcessing: isLoadingProductionPreview,
                        previewAction: { isShowingProductionPreview = true },
                        removeAction: clearSelectedProductionPreview
                    )
                    .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: draft.imageURLStrings)
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: selectedVideoURL)
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: selectedProductionPreviewURL)
            .animation(.easeInOut(duration: 0.18), value: isLoadingPhotos)
            .animation(.easeInOut(duration: 0.18), value: isLoadingCreatorClip)
            .animation(.easeInOut(duration: 0.18), value: isLoadingProductionPreview)
        }
    }

    private var productRightsOwnershipSection: some View {
        ProductRightsOwnershipSection(
            ownershipType: $draft.rightsOwnershipType,
            referenceFlags: $draft.rightsReferenceFlags,
            certificationAccepted: $draft.rightsCertificationAccepted,
            certificationAcceptedAt: $draft.rightsCertificationAcceptedAt,
            showIncompleteMessage: !draft.isRightsConfirmationComplete
        )
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                var updatedDraft = draft
                updatedDraft.demoVideoURLString = selectedVideoURL?.absoluteString ?? draft.demoVideoURLString
                updatedDraft.productionPreviewURLString = selectedProductionPreviewURL?.absoluteString ?? draft.productionPreviewURLString
                if updatedDraft.rightsCertificationAcceptedAt == nil {
                    updatedDraft.rightsCertificationAcceptedAt = Date()
                }
                updatedDraft.refreshRightsReviewFlag()
                draft = updatedDraft
                onSave(
                    updatedDraft,
                    SellerProductMediaSelection(
                        selectedVideoURL: selectedVideoURL,
                        selectedProductionPreviewURL: selectedProductionPreviewURL
                    )
                )
                dismiss()
            } label: {
                Text(title == "Add Product" ? "Save & Submit for Review" : "Submit Product Updates")
                    .font(.tbHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(PrimaryCTAButtonStyle())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.6)

            if showRightsValidationMessage || !draft.isRightsConfirmationComplete {
                Text("Complete this section before submitting your product.")
                    .font(.tbCaption)
                    .foregroundStyle(.orange)
            }

            Text(
                premiumListingBlocked
                    ? "Submit is disabled until the price is \(Money.format(cents: premiumListingThresholdCents - 1)) or below, or your shop earns verification."
                    : "This editor saves your listing locally and submits it to TenBelow for marketplace review."
            )
                .font(.tbCaption)
                .foregroundStyle(premiumListingBlocked ? .orange : .secondary)
        }
    }

    private func sellerFormField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .font(.tbBody)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
            )
    }

    private func sellerTextEditor(title: String, text: Binding<String>, lineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.tbBodyStrong)
                .foregroundStyle(TBTheme.deepSky)

            TextField(title, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.tbBody)
                .lineLimit(lineLimit, reservesSpace: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
                )
        }
    }

    private func sellerStepperCard(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                Text("\(value.wrappedValue)")
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
        )
    }

    private func mediaPickerButtonLabel(
        title: String,
        icon: String,
        isAttached: Bool = false,
        isProcessing: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            if isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .tint(TBTheme.deepSky)
            } else {
                Image(systemName: isAttached ? "checkmark.circle.fill" : "plus")
                    .font(.system(size: 12, weight: .bold))
            }
        }
        .foregroundStyle(TBTheme.deepSky)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
        )
    }

    private func productPhotoThumbnail(reference: String, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            StorefrontImageView(reference: reference) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(TBTheme.skyLight.opacity(0.30))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 108, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: TBTheme.deepSky.opacity(0.08), radius: 8, y: 4)

            Button {
                removePhoto(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }

    private var productPhotoLoadingThumbnail: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(TBTheme.skyLight.opacity(0.26))
            .overlay {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(TBTheme.deepSky)
                    Text("Adding")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky.opacity(0.8))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.68), lineWidth: 1)
            )
            .frame(width: 108, height: 108)
            .shadow(color: TBTheme.deepSky.opacity(0.06), radius: 8, y: 4)
    }

    private func mediaAttachmentRow(
        title: String,
        fileName: String,
        icon: String,
        isProcessing: Bool,
        previewAction: @escaping () -> Void,
        removeAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TBTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)
                    Text(fileName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .tint(TBTheme.accent)
            } else {
                Button("Preview") {
                    previewAction()
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(TBTheme.accent)
                .buttonStyle(.plain)

                Button("Remove") {
                    removeAction()
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 44)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
        )
    }

    private func loadSelectedImages(from items: [PhotosPickerItem]) async {
        let availableSlots = remainingPhotoSlots
        guard availableSlots > 0 else {
            await MainActor.run {
                mediaErrorMessage = "You can add up to 6 photos."
                selectedImageItems = []
            }
            return
        }

        await MainActor.run {
            isLoadingPhotos = true
            loadingPhotoPlaceholderCount = min(items.count, availableSlots)
            mediaErrorMessage = nil
        }

        var loadedReferences: [String] = []

        for item in items.prefix(availableSlots) {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            do {
                try data.write(to: outputURL, options: .atomic)
                loadedReferences.append(outputURL.absoluteString)
            } catch {
                continue
            }
        }

        await MainActor.run {
            draft.imageURLStrings.append(contentsOf: loadedReferences)
            draft.imageURLStrings = Array(draft.imageURLStrings.prefix(6))
            mediaErrorMessage = items.count > availableSlots
                ? "You can add up to 6 photos."
                : nil
            isLoadingPhotos = false
            loadingPhotoPlaceholderCount = 0
            selectedImageItems = []
        }
    }

    private func loadSelectedVideo(from item: PhotosPickerItem?) async {
        guard let item else {
            await MainActor.run {
                draft.demoVideoURLString = ""
                selectedVideoURL = nil
            }
            return
        }

        await MainActor.run {
            isLoadingCreatorClip = true
            mediaErrorMessage = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    isLoadingCreatorClip = false
                    mediaErrorMessage = "We couldn't load that video clip."
                }
                return
            }

            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)

            try data.write(to: outputURL, options: .atomic)

            await MainActor.run {
                mediaErrorMessage = nil
                draft.demoVideoURLString = outputURL.absoluteString
                selectedVideoURL = outputURL
                isLoadingCreatorClip = false
            }
        } catch {
            await MainActor.run {
                isLoadingCreatorClip = false
                mediaErrorMessage = "We couldn't load that video clip."
            }
        }
    }

    private func loadSelectedProductionPreview(from item: PhotosPickerItem?) async {
        guard let item else {
            await MainActor.run {
                draft.productionPreviewURLString = ""
                selectedProductionPreviewURL = nil
            }
            return
        }

        await MainActor.run {
            isLoadingProductionPreview = true
            mediaErrorMessage = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    isLoadingProductionPreview = false
                    mediaErrorMessage = "We couldn't load that production preview clip."
                }
                return
            }

            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)

            try data.write(to: outputURL, options: .atomic)

            await MainActor.run {
                mediaErrorMessage = nil
                draft.productionPreviewURLString = outputURL.absoluteString
                selectedProductionPreviewURL = outputURL
                isLoadingProductionPreview = false
            }
        } catch {
            await MainActor.run {
                isLoadingProductionPreview = false
                mediaErrorMessage = "We couldn't load that production preview clip."
            }
        }
    }

    private func clearSelectedVideo() {
        if let selectedVideoURL {
            if selectedVideoURL.isFileURL {
                try? FileManager.default.removeItem(at: selectedVideoURL)
            }
        }

        draft.demoVideoURLString = ""
        selectedVideoURL = nil
        selectedVideoItem = nil
    }

    private func clearSelectedProductionPreview() {
        if let selectedProductionPreviewURL {
            if selectedProductionPreviewURL.isFileURL {
                try? FileManager.default.removeItem(at: selectedProductionPreviewURL)
            }
        }

        draft.productionPreviewURLString = ""
        selectedProductionPreviewURL = nil
        selectedProductionPreviewItem = nil
    }

    private func removePhoto(at index: Int) {
        guard draft.imageURLStrings.indices.contains(index) else { return }
        let reference = draft.imageURLStrings.remove(at: index)
        if let fileURL = Product.previewMediaURL(for: reference), fileURL.isFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        mediaErrorMessage = nil
    }
}

struct SellerProductMediaSelection {
    let selectedVideoURL: URL?
    let selectedProductionPreviewURL: URL?

    static let none = SellerProductMediaSelection(
        selectedVideoURL: nil,
        selectedProductionPreviewURL: nil
    )
}

private struct AutoplayVideoPreview: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                player.seek(to: .zero)
                player.play()
            }
            .onDisappear {
                player.pause()
            }
    }
}

private enum SellerProductRemovalReason: String, CaseIterable, Identifiable {
    case noLongerSelling = "no_longer_selling"
    case needsChanges = "needs_changes"
    case outOfStock = "out_of_stock"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noLongerSelling:
            return "No longer selling it"
        case .needsChanges:
            return "Needs changes first"
        case .outOfStock:
            return "Out of stock"
        }
    }
}

enum SellerMarketplaceStatus: String, Codable {
    case draft
    case pendingReview
    case live
    case rejected
    case archived

    var title: String {
        switch self {
        case .draft: return "Draft"
        case .pendingReview: return "Pending review"
        case .live: return "Live"
        case .rejected: return "Not approved"
        case .archived: return "Archived"
        }
    }

    var subtitle: String {
        switch self {
        case .draft: return "Saved on this device"
        case .pendingReview: return "Submitted to TenBelow"
        case .live: return "Visible in marketplace"
        case .rejected: return "Hidden until you revise and resubmit"
        case .archived: return "Removed from the marketplace by TenBelow"
        }
    }

    var symbolName: String {
        switch self {
        case .draft: return "square.and.pencil"
        case .pendingReview: return "clock.badge.checkmark"
        case .live: return "checkmark.seal.fill"
        case .rejected: return "xmark.circle.fill"
        case .archived: return "archivebox.fill"
        }
    }

    /// Maps server catalog fields to the seller-facing workflow chip.
    static func fromServerProduct(_ p: RemoteProduct) -> SellerMarketplaceStatus {
        let s = (p.approvalStatus ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch s {
        case "archived":
            return .archived
        case "rejected":
            return .rejected
        case "submitted":
            return .pendingReview
        case "approved":
            return (p.isActive && p.isApproved) ? .live : .pendingReview
        default:
            return (p.isActive && p.isApproved) ? .live : .pendingReview
        }
    }
}

struct SellerProductsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore
    @AppStorage("catalogRefreshToken") private var catalogRefreshToken = 0
    @AppStorage("sellerPreviewMode") private var sellerPreviewMode = false

    let seller: SellerProfile
    let products: [Product]
    let startInAddMode: Bool

    @State private var productDrafts: [SellerProductDraft]
    @State private var selectedDraft: SellerProductDraft?
    @State private var isShowingAddSheet = false
    @State private var hasPresentedInitialAdd = false
    @State private var syncMessage: String?
    @State private var pendingDeleteDraft: SellerProductDraft?
    @State private var draggingProductId: String?
    @State private var productSwipeOffset: CGFloat = 0
    @State private var isRefreshingInventory = false
    @State private var submittingProductIDs = Set<String>()
    @State private var productIDsAwaitingServerConfirmation = Set<String>()
    @State private var locallyDeletedProductIDs: Set<String>

    init(
        seller: SellerProfile = .sample,
        products: [Product] = MockData.products,
        startInAddMode: Bool = false
    ) {
        self.seller = seller
        self.products = products
        self.startInAddMode = startInAddMode
        let deletedIDs = SellerDeletedProductStorage.load(for: seller.id)
        _productDrafts = State(
            initialValue: SellerProductDraft.load(for: seller.id, fallbackProducts: products)
                .filter { !deletedIDs.contains($0.id) }
        )
        _locallyDeletedProductIDs = State(initialValue: deletedIDs)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                headerCard
                inventorySnapshotCard

                if let syncMessage {
                    Text(syncMessage)
                        .font(.tbCaption)
                        .foregroundStyle(syncMessageForeground(for: syncMessage))
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(productDrafts) { draft in
                    sellerProductSwipeRow(draft)
                }

                if productDrafts.isEmpty {
                    Text("No products yet. Add your first listing to get started.")
                        .font(.tbBody)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding(TBTheme.spacingLG)
        }
        .task {
            await refreshInventoryFromServer()
        }
        .refreshable {
            await refreshInventoryFromServer(showFailureMessage: true)
        }
        .onChange(of: catalogRefreshToken) { _, _ in
            Task { await refreshInventoryFromServer() }
        }
        .onChange(of: catalog.contentRevision) { _, _ in
            applyApprovedCatalogProductsToDrafts()
        }
        .background(TBFrostBackground())
        .navigationTitle("My Products")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await presentAddProductFlow() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TBTheme.deepSky)
                }
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            NavigationStack {
                AddProductView(
                    title: "Add Product",
                    initialDraft: .new(sellerId: seller.id)
                ) { savedDraft, mediaSelection in
                    let submittedDraft = draftForMarketplaceSubmission(savedDraft)
                    restoreLocallyDeletedProductIfNeeded(submittedDraft.id)
                    productDrafts.insert(submittedDraft, at: 0)
                    persistDrafts()
                    localProducts.saveDraft(submittedDraft)
                    markSubmissionStarted(for: submittedDraft.id)
                    Task {
                        await syncDraftToServer(submittedDraft, mediaSelection: mediaSelection)
                    }
                }
            }
        }
        .sheet(item: $selectedDraft) { draft in
            NavigationStack {
                AddProductView(
                    title: "Edit Product",
                    initialDraft: draft
                ) { updatedDraft, mediaSelection in
                    let submittedDraft = draftForMarketplaceSubmission(updatedDraft)
                    restoreLocallyDeletedProductIfNeeded(submittedDraft.id)
                    if let index = productDrafts.firstIndex(where: { $0.id == submittedDraft.id }) {
                        productDrafts[index] = submittedDraft
                    } else {
                        productDrafts.insert(submittedDraft, at: 0)
                    }
                    persistDrafts()
                    localProducts.saveDraft(submittedDraft)
                    markSubmissionStarted(for: submittedDraft.id)
                    Task {
                        await syncDraftToServer(submittedDraft, mediaSelection: mediaSelection)
                    }
                }
            }
        }
        .onAppear {
            guard startInAddMode, !hasPresentedInitialAdd else { return }
            hasPresentedInitialAdd = true
            Task { await presentAddProductFlow() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshInventoryFromServer() }
        }
        .confirmationDialog(
            "Delete product?",
            isPresented: Binding(
                get: { pendingDeleteDraft != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteDraft = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteDraft
        ) { draft in
            ForEach(SellerProductRemovalReason.allCases) { reason in
                Button(reason.title, role: .destructive) {
                    deleteDraft(draft, reason: reason)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { draft in
            Text("Why are you removing \(draft.name.isEmpty ? "this product" : draft.name)?")
        }
    }

    private func presentAddProductFlow() async {
        await MainActor.run { isShowingAddSheet = true }

        guard !sellerPreviewMode else { return }
        await MarketplaceAuthSession.syncAfterIdentityChange()
        await sellerSubscription.refresh()
    }

    private func sellerProductSwipeRow(_ draft: SellerProductDraft) -> some View {
        sellerProductCard(draft)
        .offset(x: draggingProductId == draft.id ? productSwipeOffset : 0)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            selectedDraft = draft
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    guard value.translation.width < 0,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    draggingProductId = draft.id
                    productSwipeOffset = max(value.translation.width, -42)
                }
                .onEnded { value in
                    guard value.translation.width < -56,
                          abs(value.translation.width) > abs(value.translation.height) else {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                            productSwipeOffset = 0
                            draggingProductId = nil
                        }
                        return
                    }
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.88)) {
                        draggingProductId = draft.id
                        productSwipeOffset = -34
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        pendingDeleteDraft = draft
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                            productSwipeOffset = 0
                            draggingProductId = nil
                        }
                    }
                }
        )
    }

    private var headerCard: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Manage product details")
                    .font(.tbHeadline)
                    .foregroundStyle(TBTheme.deepSky)

                Text("Update name, price, shipping, details, and media shown on product pages.")
                    .font(.tbBody)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
    }

    private var inventorySnapshotCard: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inventory snapshot")
                    .font(.tbHeadline)
                    .foregroundStyle(TBTheme.deepSky)

                HStack(spacing: 12) {
                    productMetricCard(
                        title: "Products",
                        value: "\(productDrafts.count)",
                        subtitle: productDrafts.isEmpty ? "Add your first listing" : "Ready to manage"
                    )

                    productMetricCard(
                        title: "Total Value",
                        value: totalListingValueText,
                        subtitle: "Across uploaded products"
                    )
                }

                if pendingReviewCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TBTheme.icyBlue)
                        Text("\(pendingReviewCount) listing\(pendingReviewCount == 1 ? "" : "s") awaiting marketplace review")
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)
                    }
                }

                if rejectedOrArchivedCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.orange.opacity(0.85))
                        Text("\(rejectedOrArchivedCount) listing\(rejectedOrArchivedCount == 1 ? "" : "s") not live (rejected or archived)")
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let latestDraft = productDrafts.first {
                    Text("Latest update: \(latestDraft.name.isEmpty ? "Untitled product" : latestDraft.name)")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sellerProductCard(_ draft: SellerProductDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.name)
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)

                    Text(draft.priceDisplay)
                        .font(.tbMeta)
                        .foregroundStyle(TBTheme.icyBlue)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: draft.marketplaceStatus.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                    Text(draft.marketplaceStatus.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(statusTint(for: draft.marketplaceStatus))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(statusBackground(for: draft.marketplaceStatus), in: Capsule(style: .continuous))
            }

            Text(sellerProductSubtitle(for: draft))
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let notes = draft.serverReviewNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty,
               draft.marketplaceStatus == .rejected {
                Text("Feedback: \(notes)")
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                sellerMetaPill(draft.category.rawValue)
                sellerMetaPill(draft.material)
                sellerMetaPill("\(draft.shipsInMinDays)-\(draft.shipsInMaxDays) days")
            }
        }
        .padding(16)
        .background(cardBackground(for: draft.marketplaceStatus), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(cardBorderColor(for: draft.marketplaceStatus), lineWidth: 0.9)
        )
        .shadow(color: cardShadowColor(for: draft.marketplaceStatus), radius: 10, y: 5)
    }

    private func sellerMetaPill(_ text: String) -> some View {
        Text(text)
            .font(.tbCaption)
            .foregroundStyle(TBTheme.deepSky)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(TBTheme.skyLight.opacity(0.4), in: Capsule())
    }

    private func productMetricCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.tbCaption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)

            Text(subtitle)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
        )
    }

    private var totalListingValueText: String {
        guard !productDrafts.isEmpty else { return "$0" }
        let total = productDrafts.map(\.priceCents).reduce(0, +)
        return Money.format(cents: total)
    }

    private var pendingReviewCount: Int {
        productDrafts.filter { $0.marketplaceStatus == .pendingReview }.count
    }

    private var rejectedOrArchivedCount: Int {
        productDrafts.filter { $0.marketplaceStatus == .rejected || $0.marketplaceStatus == .archived }.count
    }

    private func syncMessageForeground(for message: String) -> Color {
        if message.contains("Loading") || message.contains("Submitting") || message.contains("review queue") {
            return TBTheme.icyBlue
        }
        if message.contains("Couldn’t") || message.contains("failed") || message.contains("Failed") {
            return .orange
        }
        if message.contains("not approved") || message.contains("rejected") || message.contains("archived") || message.contains("Archived") {
            return .red
        }
        if message.contains("device") {
            return .orange
        }
        return .green
    }

    private func refreshInventoryFromServer(showFailureMessage: Bool = false) async {
        var shouldStartRefresh = false
        await MainActor.run {
            if !isRefreshingInventory {
                isRefreshingInventory = true
                shouldStartRefresh = true
                if submittingProductIDs.isEmpty {
                    syncMessage = "Loading product status..."
                }
            }
        }
        guard shouldStartRefresh else { return }

        defer {
            Task { @MainActor in
                isRefreshingInventory = false
            }
        }

        do {
            await MarketplaceAuthSession.syncAfterIdentityChange()
            await catalog.load()
            let remote = try await SellerAPI.fetchSellerProducts(sellerId: seller.id)
            let remoteProductIDs = Set(remote.map(\.id))
            let draftsNeedingRetry = await MainActor.run {
                mergeRemoteInventory(remote)
                _ = applyApprovedCatalogProductsToDrafts()
                let retryDrafts = pendingDraftsMissingFromServer(remoteProductIDs: remoteProductIDs)
                if let m = syncMessage,
                   m.contains("Loading product status")
                    || m.contains("Couldn’t refresh")
                    || m.contains("submission failed") {
                    syncMessage = nil
                }
                if !retryDrafts.isEmpty {
                    syncMessage = "Retrying marketplace submission so it appears in the admin review queue..."
                }
                return retryDrafts
            }
            for draft in draftsNeedingRetry {
                await syncDraftToServer(draft, mediaSelection: .none)
            }
        } catch {
            await MainActor.run {
                if applyApprovedCatalogProductsToDrafts() {
                    syncMessage = nil
                } else if !submittingProductIDs.isEmpty {
                    syncMessage = "Submitting listing for TenBelow review..."
                } else if !showFailureMessage {
                    syncMessage = nil
                } else {
                    syncMessage = "Couldn’t refresh listing status from the server. Pull to try again."
                }
            }
        }
    }

    private func mergeRemoteInventory(_ remote: [RemoteProduct]) {
        let visibleRemote = remote.filter {
            !locallyDeletedProductIDs.contains($0.id)
                && SellerMarketplaceStatus.fromServerProduct($0) != .archived
        }
        let remoteById = Dictionary(uniqueKeysWithValues: visibleRemote.map { ($0.id, $0) })
        let remoteProductIDs = Set(remoteById.keys)
        var removedProductIDs = Set<String>()
        var result = productDrafts.compactMap { draft -> SellerProductDraft? in
            guard !locallyDeletedProductIDs.contains(draft.id) else { return nil }
            if remoteProductIDs.contains(draft.id) {
                return draft
            }
            if submittingProductIDs.contains(draft.id) || productIDsAwaitingServerConfirmation.contains(draft.id) {
                return draft
            }
            removedProductIDs.insert(draft.id)
            return nil
        }
        for i in result.indices {
            if let r = remoteById[result[i].id] {
                result[i].marketplaceStatus = SellerMarketplaceStatus.fromServerProduct(r)
                let trimmed = r.reviewNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                result[i].serverReviewNotes = trimmed.isEmpty ? nil : trimmed
                productIDsAwaitingServerConfirmation.remove(result[i].id)
            } else if result[i].marketplaceStatus == .pendingReview {
                productIDsAwaitingServerConfirmation.insert(result[i].id)
            }
        }
        let localIds = Set(result.map(\.id))
        for r in visibleRemote where !localIds.contains(r.id) {
            result.append(SellerProductDraft.fromRemoteProduct(r))
            productIDsAwaitingServerConfirmation.remove(r.id)
        }
        productDrafts = result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        persistDrafts()
        for productId in removedProductIDs {
            localProducts.removeDraft(productId: productId)
            catalog.removeRemoteProduct(productId: productId)
        }
        for d in productDrafts {
            localProducts.saveDraft(d)
        }
    }

    private func pendingDraftsMissingFromServer(remoteProductIDs: Set<String>) -> [SellerProductDraft] {
        productDrafts.filter { draft in
            draft.marketplaceStatus == .pendingReview
                && !locallyDeletedProductIDs.contains(draft.id)
                && !remoteProductIDs.contains(draft.id)
                && !submittingProductIDs.contains(draft.id)
        }
    }

    @discardableResult
    private func applyApprovedCatalogProductsToDrafts() -> Bool {
        let liveSellerProducts = catalog.products.filter {
            $0.sellerId == seller.id && $0.isActive && $0.isApproved && !locallyDeletedProductIDs.contains($0.id)
        }
        guard !liveSellerProducts.isEmpty else { return false }

        let liveById = Dictionary(uniqueKeysWithValues: liveSellerProducts.map { ($0.id, $0) })
        var didChange = false
        var result = productDrafts

        for index in result.indices {
            guard let remote = liveById[result[index].id] else { continue }
            let nextStatus = SellerMarketplaceStatus.fromServerProduct(remote)
            if result[index].marketplaceStatus != nextStatus || result[index].serverReviewNotes != nil {
                result[index].marketplaceStatus = nextStatus
                result[index].serverReviewNotes = nil
                didChange = true
            }
        }

        guard didChange else { return false }
        productDrafts = result
        persistDrafts()
        for draft in productDrafts {
            localProducts.saveDraft(draft)
        }
        return true
    }

    private func persistDrafts() {
        SellerProductDraft.store(productDrafts, for: seller.id)
    }

    private func restoreLocallyDeletedProductIfNeeded(_ productId: String) {
        guard locallyDeletedProductIDs.remove(productId) != nil else { return }
        SellerDeletedProductStorage.store(locallyDeletedProductIDs, for: seller.id)
    }

    private func draftForMarketplaceSubmission(_ draft: SellerProductDraft) -> SellerProductDraft {
        var submittedDraft = draft
        submittedDraft.marketplaceStatus = .pendingReview
        submittedDraft.serverReviewNotes = nil
        return submittedDraft
    }

    private func markSubmissionStarted(for productId: String) {
        submittingProductIDs.insert(productId)
        productIDsAwaitingServerConfirmation.insert(productId)
        syncMessage = "Submitting listing for TenBelow review..."
    }

    private func markSubmissionFinished(for productId: String) {
        submittingProductIDs.remove(productId)
    }

    private func deleteDraft(_ draft: SellerProductDraft, reason: SellerProductRemovalReason) {
        locallyDeletedProductIDs.insert(draft.id)
        SellerDeletedProductStorage.store(locallyDeletedProductIDs, for: seller.id)
        submittingProductIDs.remove(draft.id)
        productIDsAwaitingServerConfirmation.remove(draft.id)
        productDrafts.removeAll { $0.id == draft.id }
        persistDrafts()
        localProducts.removeDraft(productId: draft.id)
        catalog.removeRemoteProduct(productId: draft.id)
        catalogRefreshToken += 1
        if selectedDraft?.id == draft.id {
            selectedDraft = nil
        }
        syncMessage = "Removed from My Products. Reason: \(reason.title)."
        pendingDeleteDraft = nil
        Task {
            await removeDraftFromServer(productId: draft.id, reason: reason)
        }
    }

    private func removeDraftFromServer(productId: String, reason: SellerProductRemovalReason) async {
        do {
            await MarketplaceAuthSession.syncAfterIdentityChange()
            try await SellerAPI.removeProduct(
                sellerId: seller.id,
                productId: productId,
                reason: reason.rawValue
            )
            await MainActor.run {
                catalogRefreshToken += 1
            }
        } catch {
            await MainActor.run {
                let details = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                if details.isEmpty || details == "The operation couldn’t be completed." {
                    syncMessage = "Removed from this device. Server removal failed for now."
                } else {
                    syncMessage = "Removed from this device. Server removal failed for now. \(details)"
                }
            }
        }
    }

    private func syncDraftToServer(
        _ draft: SellerProductDraft,
        mediaSelection: SellerProductMediaSelection
    ) async {
        guard !locallyDeletedProductIDs.contains(draft.id) else { return }

        await MainActor.run {
            markSubmissionStarted(for: draft.id)
            let submittedDraft = draftForMarketplaceSubmission(draft)
            if let index = productDrafts.firstIndex(where: { $0.id == submittedDraft.id }) {
                productDrafts[index] = submittedDraft
            } else {
                productDrafts.insert(submittedDraft, at: 0)
            }
            persistDrafts()
            localProducts.saveDraft(submittedDraft)
        }

        let fallbackProduct = products.first(where: { $0.id == draft.id })
            ?? localProducts.product(withId: draft.id)
        let uploadedImageURLStrings = await uploadImagesIfNeeded(
            draft.imageURLStrings,
            draft: draft
        )
        let uploadedDemoVideoURLString = await uploadVideoIfNeeded(
            mediaSelection.selectedVideoURL,
            draft: draft,
            fallbackURLString: draft.demoVideoURLString,
            mediaKind: "demo-video"
        )
        let uploadedProductionPreviewURLString = await uploadVideoIfNeeded(
            mediaSelection.selectedProductionPreviewURL,
            draft: draft,
            fallbackURLString: draft.productionPreviewURLString,
            mediaKind: "production-preview"
        )
        var syncedDraft = draft
        syncedDraft.imageURLStrings = uploadedImageURLStrings
        syncedDraft.demoVideoURLString = uploadedDemoVideoURLString
        syncedDraft.productionPreviewURLString = uploadedProductionPreviewURLString
        if syncedDraft.rightsCertificationAccepted,
           syncedDraft.rightsCertificationAcceptedAt == nil {
            syncedDraft.rightsCertificationAcceptedAt = Date()
        }
        syncedDraft.refreshRightsReviewFlag()
        let request = UpsertSellerProductRequest(
            name: syncedDraft.name.isEmpty ? "Untitled Product" : syncedDraft.name,
            priceCents: max(syncedDraft.priceCents, 0),
            category: syncedDraft.category.rawValue,
            imageURLs: uploadedImageURLStrings.isEmpty ? (fallbackProduct?.imageNames ?? []) : uploadedImageURLStrings,
            demoVideoURL: uploadedDemoVideoURLString.isEmpty ? fallbackProduct?.demoVideoURL?.absoluteString : uploadedDemoVideoURLString,
            productionPreviewURL: uploadedProductionPreviewURLString.isEmpty ? fallbackProduct?.productionPreviewURL?.absoluteString : uploadedProductionPreviewURLString,
            material: syncedDraft.material.isEmpty ? "PLA+" : syncedDraft.material,
            durabilityNote: syncedDraft.durabilityNote.isEmpty ? "Built for everyday use." : syncedDraft.durabilityNote,
            careWarnings: syncedDraft.warningLines.isEmpty ? ["Handle with care."] : syncedDraft.warningLines,
            shipsInMinDays: min(syncedDraft.shipsInMinDays, syncedDraft.shipsInMaxDays),
            shipsInMaxDays: max(syncedDraft.shipsInMinDays, syncedDraft.shipsInMaxDays),
            isDrop: false,
            isActive: false,
            isApproved: false,
            rightsOwnershipType: syncedDraft.rightsOwnershipType,
            rightsReferenceFlags: syncedDraft.rightsReferenceFlags,
            rightsCertificationAccepted: syncedDraft.rightsCertificationAccepted,
            rightsCertificationAcceptedAt: syncedDraft.rightsCertificationAcceptedAt,
            requiresManualReview: syncedDraft.requiresManualReview,
            reviewReason: syncedDraft.reviewReason
        )

        do {
            let remoteProduct = try await SellerAPI.upsertProduct(
                sellerId: seller.id,
                productId: draft.id,
                product: request
            )
            await MainActor.run {
                syncedDraft.marketplaceStatus = SellerMarketplaceStatus.fromServerProduct(remoteProduct)
                let trimmed = remoteProduct.reviewNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                syncedDraft.serverReviewNotes = trimmed.isEmpty ? nil : trimmed
                if let index = productDrafts.firstIndex(where: { $0.id == draft.id }) {
                    productDrafts[index] = syncedDraft
                }
                persistDrafts()
                localProducts.saveDraft(syncedDraft)
                catalog.upsertRemoteProduct(remoteProduct)
                catalogRefreshToken += 1
                markSubmissionFinished(for: draft.id)
                productIDsAwaitingServerConfirmation.remove(draft.id)
                syncMessage = syncSummaryMessage(for: syncedDraft.marketplaceStatus)
            }
        } catch {
            await MainActor.run {
                markSubmissionFinished(for: draft.id)
                let details = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                if details.isEmpty || details == "The operation couldn’t be completed." {
                    syncMessage = "Saved on this device. Marketplace submission failed for now."
                } else {
                    syncMessage = "Saved on this device. Marketplace submission failed for now. \(details)"
                }
            }
        }
    }

    private func syncSummaryMessage(for status: SellerMarketplaceStatus) -> String {
        switch status {
        case .live:
            return "Saved and synced to your live store."
        case .pendingReview:
            return "Saved and submitted for TenBelow review."
        case .rejected:
            return "Saved. This listing was not approved — review feedback and resubmit when ready."
        case .archived:
            return "Saved. This listing is archived and hidden from the marketplace."
        case .draft:
            return "Saved on this device."
        }
    }

    private func sellerProductSubtitle(for draft: SellerProductDraft) -> String {
        if submittingProductIDs.contains(draft.id) {
            return "Submitting to TenBelow..."
        }
        if productIDsAwaitingServerConfirmation.contains(draft.id),
           draft.marketplaceStatus == .pendingReview {
            return "Waiting for TenBelow server confirmation"
        }
        return draft.marketplaceStatus.subtitle
    }

    private func statusTint(for status: SellerMarketplaceStatus) -> Color {
        switch status {
        case .draft:
            return TBTheme.deepSky
        case .pendingReview:
            return TBTheme.icyBlue
        case .live:
            return .green
        case .rejected:
            return .red
        case .archived:
            return Color.secondary
        }
    }

    private func statusBackground(for status: SellerMarketplaceStatus) -> Color {
        switch status {
        case .draft:
            return TBTheme.skyLight.opacity(0.28)
        case .pendingReview:
            return TBTheme.skyBlue.opacity(0.14)
        case .live:
            return Color.green.opacity(0.14)
        case .rejected:
            return Color.red.opacity(0.12)
        case .archived:
            return Color.gray.opacity(0.12)
        }
    }

    private func cardBackground(for status: SellerMarketplaceStatus) -> Color {
        switch status {
        case .live:
            return Color.green.opacity(0.08)
        case .rejected:
            return Color.red.opacity(0.07)
        case .archived:
            return Color.gray.opacity(0.10)
        case .pendingReview:
            return Color.white.opacity(0.78)
        case .draft:
            return Color.white.opacity(0.76)
        }
    }

    private func cardBorderColor(for status: SellerMarketplaceStatus) -> Color {
        switch status {
        case .live:
            return Color.green.opacity(0.24)
        case .rejected:
            return Color.red.opacity(0.24)
        case .archived:
            return Color.gray.opacity(0.18)
        case .pendingReview:
            return TBTheme.skyBlue.opacity(0.16)
        case .draft:
            return TBTheme.skyBlue.opacity(0.12)
        }
    }

    private func cardShadowColor(for status: SellerMarketplaceStatus) -> Color {
        switch status {
        case .live:
            return Color.green.opacity(0.08)
        case .rejected:
            return Color.red.opacity(0.08)
        case .archived:
            return Color.black.opacity(0.02)
        case .pendingReview, .draft:
            return Color.black.opacity(0.03)
        }
    }

    private func uploadImagesIfNeeded(
        _ imageReferences: [String],
        draft: SellerProductDraft
    ) async -> [String] {
        let trimmedReferences = imageReferences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedReferences.isEmpty else { return [] }

        var uploadedURLs: [String] = []
        for (index, reference) in trimmedReferences.prefix(6).enumerated() {
            if let remoteURL = Product.mediaURL(for: reference) {
                uploadedURLs.append(remoteURL.absoluteString)
                continue
            }

            guard let localURL = Product.previewMediaURL(for: reference), localURL.isFileURL else {
                uploadedURLs.append(reference)
                continue
            }

            guard let imageData = try? Data(contentsOf: localURL) else {
                uploadedURLs.append(reference)
                continue
            }

            let fileExtension = localURL.pathExtension.lowercased().isEmpty ? "jpg" : localURL.pathExtension.lowercased()

            do {
                let url = try await SellerAPI.uploadMedia(
                    sellerId: seller.id,
                    productId: draft.id,
                    mediaKind: "image",
                    slot: "\(index)",
                    fileExtension: fileExtension,
                    contentType: imageContentType(for: fileExtension),
                    data: imageData
                )
                uploadedURLs.append(url)
            } catch {
                uploadedURLs.append(reference)
            }
        }

        return uploadedURLs
    }

    private func uploadVideoIfNeeded(
        _ selectedVideoURL: URL?,
        draft: SellerProductDraft,
        fallbackURLString: String,
        mediaKind: String
    ) async -> String {
        guard let selectedVideoURL else { return fallbackURLString }
        guard selectedVideoURL.isFileURL, let videoData = try? Data(contentsOf: selectedVideoURL) else {
            return selectedVideoURL.absoluteString
        }

        let fileExtension = selectedVideoURL.pathExtension.isEmpty ? "mov" : selectedVideoURL.pathExtension
        do {
            return try await SellerAPI.uploadMedia(
                sellerId: seller.id,
                productId: draft.id,
                mediaKind: mediaKind,
                slot: "0",
                fileExtension: fileExtension,
                contentType: "video/\(fileExtension == "mp4" ? "mp4" : "quicktime")",
                data: videoData
            )
        } catch {
            return fallbackURLString.isEmpty ? selectedVideoURL.absoluteString : fallbackURLString
        }
    }

    private func imageContentType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        case "heic", "heif":
            return "image/heic"
        default:
            return "image/jpeg"
        }
    }
}

struct SellerProductDraft: Identifiable, Codable {
    let id: String
    var sellerId: String
    var name: String
    var priceText: String
    var category: Category
    var imageURLStrings: [String]
    var demoVideoURLString: String
    var material: String
    var productionNote: String
    var durabilityNote: String
    var careWarningsText: String
    var shipsInMinDays: Int
    var shipsInMaxDays: Int
    /// Separate post-purchase clip shown in buyer Order Details.
    /// This is intentionally independent from public product photos/demo media.
    var productionPreviewURLString: String = ""
    var marketplaceStatusRaw: String? = nil
    /// Admin rejection rationale from the server (shown when `marketplaceStatus` is `.rejected`).
    var serverReviewNotes: String? = nil
    var rightsOwnershipType: String?
    var rightsReferenceFlags: [String] = []
    var rightsCertificationAccepted: Bool = false
    var rightsCertificationAcceptedAt: Date?
    var requiresManualReview: Bool = false
    var reviewReason: String?

    enum CodingKeys: String, CodingKey {
        case id, sellerId, name, priceText, category, imageURLStrings, demoVideoURLString
        case material, productionNote, durabilityNote, careWarningsText, shipsInMinDays, shipsInMaxDays
        case productionPreviewURLString, marketplaceStatusRaw, serverReviewNotes
        case rightsOwnershipType, rightsReferenceFlags, rightsCertificationAccepted
        case rightsCertificationAcceptedAt, requiresManualReview, reviewReason
    }

    init(product: Product) {
        id = product.id
        sellerId = product.sellerId
        name = product.name
        priceText = String(format: "%.2f", Double(product.priceCents) / 100.0)
        category = product.category
        imageURLStrings = product.imageNames
        demoVideoURLString = product.demoVideoURL?.absoluteString ?? ""
        material = product.material
        productionNote = product.productionNote
        durabilityNote = product.durabilityNote
        careWarningsText = product.careWarnings.joined(separator: "\n")
        shipsInMinDays = product.shipsInDays.lowerBound
        shipsInMaxDays = product.shipsInDays.upperBound
        productionPreviewURLString = product.productionPreviewURL?.absoluteString ?? ""
        marketplaceStatusRaw = SellerMarketplaceStatus.live.rawValue
        serverReviewNotes = nil
        rightsOwnershipType = product.rightsOwnershipType
        rightsReferenceFlags = product.rightsReferenceFlags
        rightsCertificationAccepted = product.rightsCertificationAccepted
        rightsCertificationAcceptedAt = product.rightsCertificationAcceptedAt
        requiresManualReview = product.requiresManualReview
        reviewReason = product.reviewReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sellerId = try container.decode(String.self, forKey: .sellerId)
        name = try container.decode(String.self, forKey: .name)
        priceText = try container.decode(String.self, forKey: .priceText)
        category = try container.decode(Category.self, forKey: .category)
        imageURLStrings = try container.decode([String].self, forKey: .imageURLStrings)
        demoVideoURLString = try container.decode(String.self, forKey: .demoVideoURLString)
        material = try container.decode(String.self, forKey: .material)
        productionNote = try container.decode(String.self, forKey: .productionNote)
        durabilityNote = try container.decode(String.self, forKey: .durabilityNote)
        careWarningsText = try container.decode(String.self, forKey: .careWarningsText)
        shipsInMinDays = try container.decode(Int.self, forKey: .shipsInMinDays)
        shipsInMaxDays = try container.decode(Int.self, forKey: .shipsInMaxDays)
        productionPreviewURLString = try container.decodeIfPresent(String.self, forKey: .productionPreviewURLString) ?? ""
        marketplaceStatusRaw = try container.decodeIfPresent(String.self, forKey: .marketplaceStatusRaw)
        serverReviewNotes = try container.decodeIfPresent(String.self, forKey: .serverReviewNotes)
        rightsOwnershipType = try container.decodeIfPresent(String.self, forKey: .rightsOwnershipType)
        rightsReferenceFlags = try container.decodeIfPresent([String].self, forKey: .rightsReferenceFlags) ?? []
        rightsCertificationAccepted = try container.decodeIfPresent(Bool.self, forKey: .rightsCertificationAccepted) ?? false
        rightsCertificationAcceptedAt = try container.decodeIfPresent(Date.self, forKey: .rightsCertificationAcceptedAt)
        requiresManualReview = try container.decodeIfPresent(Bool.self, forKey: .requiresManualReview) ?? false
        reviewReason = try container.decodeIfPresent(String.self, forKey: .reviewReason)
    }

    static func new(sellerId: String = SellerProfile.sample.id) -> SellerProductDraft {
        SellerProductDraft(
            id: UUID().uuidString,
            sellerId: sellerId,
            name: "",
            priceText: "",
            category: .desk,
            imageURLStrings: [],
            demoVideoURLString: "",
            material: "",
            productionNote: "Printed fresh when you order",
            durabilityNote: "",
            careWarningsText: "",
            shipsInMinDays: 2,
            shipsInMaxDays: 4,
            productionPreviewURLString: "",
            marketplaceStatusRaw: SellerMarketplaceStatus.draft.rawValue,
            serverReviewNotes: nil,
            rightsOwnershipType: nil,
            rightsReferenceFlags: [],
            rightsCertificationAccepted: false,
            rightsCertificationAcceptedAt: nil,
            requiresManualReview: false,
            reviewReason: nil
        )
    }

    private init(
        id: String,
        sellerId: String,
        name: String,
        priceText: String,
        category: Category,
        imageURLStrings: [String],
        demoVideoURLString: String,
        material: String,
        productionNote: String,
        durabilityNote: String,
        careWarningsText: String,
        shipsInMinDays: Int,
        shipsInMaxDays: Int,
        productionPreviewURLString: String,
        marketplaceStatusRaw: String? = nil,
        serverReviewNotes: String? = nil,
        rightsOwnershipType: String? = nil,
        rightsReferenceFlags: [String] = [],
        rightsCertificationAccepted: Bool = false,
        rightsCertificationAcceptedAt: Date? = nil,
        requiresManualReview: Bool = false,
        reviewReason: String? = nil
    ) {
        self.id = id
        self.sellerId = sellerId
        self.name = name
        self.priceText = priceText
        self.category = category
        self.imageURLStrings = imageURLStrings
        self.demoVideoURLString = demoVideoURLString
        self.material = material
        self.productionNote = productionNote
        self.durabilityNote = durabilityNote
        self.careWarningsText = careWarningsText
        self.shipsInMinDays = shipsInMinDays
        self.shipsInMaxDays = shipsInMaxDays
        self.productionPreviewURLString = productionPreviewURLString
        self.marketplaceStatusRaw = marketplaceStatusRaw
        self.serverReviewNotes = serverReviewNotes
        self.rightsOwnershipType = rightsOwnershipType
        self.rightsReferenceFlags = rightsReferenceFlags
        self.rightsCertificationAccepted = rightsCertificationAccepted
        self.rightsCertificationAcceptedAt = rightsCertificationAcceptedAt
        self.requiresManualReview = requiresManualReview
        self.reviewReason = reviewReason
    }

    static func fromRemoteProduct(_ p: RemoteProduct) -> SellerProductDraft {
        let storefront = p.asStorefrontProduct()
        let notes = p.reviewNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let formatter = ISO8601DateFormatter()
        return SellerProductDraft(
            id: p.id,
            sellerId: p.sellerId,
            name: p.name,
            priceText: String(format: "%.2f", Double(p.priceCents) / 100.0),
            category: storefront.category,
            imageURLStrings: p.imageURLs,
            demoVideoURLString: p.demoVideoURL ?? "",
            material: p.material,
            productionNote: "Printed fresh when you order",
            durabilityNote: p.durabilityNote,
            careWarningsText: p.careWarnings.joined(separator: "\n"),
            shipsInMinDays: p.shipsInMinDays,
            shipsInMaxDays: p.shipsInMaxDays,
            productionPreviewURLString: p.productionPreviewURL ?? "",
            marketplaceStatusRaw: SellerMarketplaceStatus.fromServerProduct(p).rawValue,
            serverReviewNotes: notes.isEmpty ? nil : notes,
            rightsOwnershipType: p.rightsOwnershipType,
            rightsReferenceFlags: p.rightsReferenceFlags ?? [],
            rightsCertificationAccepted: p.rightsCertificationAccepted ?? false,
            rightsCertificationAcceptedAt: p.rightsCertificationAcceptedAt.flatMap { formatter.date(from: $0) },
            requiresManualReview: p.requiresManualReview ?? false,
            reviewReason: p.reviewReason
        )
    }

    var priceCents: Int {
        Int((Double(priceText) ?? 0) * 100)
    }

    var priceDisplay: String {
        Money.format(cents: priceCents)
    }

    var warningLines: [String] {
        careWarningsText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var marketplaceStatus: SellerMarketplaceStatus {
        get { SellerMarketplaceStatus(rawValue: marketplaceStatusRaw ?? "") ?? .draft }
        set { marketplaceStatusRaw = newValue.rawValue }
    }

    var isRightsConfirmationComplete: Bool {
        rightsOwnershipType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && !rightsReferenceFlags.isEmpty
            && rightsCertificationAccepted
    }

    mutating func refreshRightsReviewFlag() {
        requiresManualReview = ProductRightsReview.requiresManualReview(
            ownershipType: rightsOwnershipType,
            referenceFlags: rightsReferenceFlags
        )
        reviewReason = ProductRightsReview.reviewReason(referenceFlags: rightsReferenceFlags)
    }
}

struct SellerStorePreviewView: View {
    var seller: SellerProfile?
    var products: [Product] = []

    var body: some View {
        if let seller {
            PublicSellerProfileView(
                seller: seller,
                products: previewDisplayProducts,
                previewDraftIDs: previewDraftIDs
            )
        } else {
            Text("Store Preview").navigationTitle("Store Preview")
        }
    }

    /// Draft-backed listings when present; otherwise published products for this seller.
    private var previewDisplayProducts: [Product] {
        guard let seller else { return products }
        let fromDrafts = productsFromDrafts(for: seller)
        if !fromDrafts.isEmpty { return fromDrafts }
        let published = products.filter { $0.sellerId == seller.id }
        if !published.isEmpty { return published }
        return []
    }

    private func productsFromDrafts(for seller: SellerProfile) -> [Product] {
        let drafts = SellerProductDraft.load(for: seller.id, fallbackProducts: products)
        return drafts.map { draft in
            Product(draft: draft, fallbackImageNames: fallbackImageNames(for: draft, sellerId: seller.id))
        }
    }

    private func fallbackImageNames(for draft: SellerProductDraft, sellerId: String) -> [String] {
        products.first(where: { $0.id == draft.id })?.imageNames ??
        products.first(where: { $0.sellerId == sellerId })?.imageNames ??
        ["products_image"]
    }

    private var previewDraftIDs: Set<String> {
        Set(localDrafts.map(\.id))
    }

    private var localDrafts: [SellerProductDraft] {
        guard let seller else { return [] }
        guard let data = UserDefaults.standard.data(forKey: SellerProductDraftStorage.key(for: seller.id)),
              let saved = try? JSONDecoder().decode([SellerProductDraft].self, from: data) else {
            return []
        }
        return saved
    }
}

struct SellerOrdersView: View {
    var body: some View { Text("Manage Orders").navigationTitle("Manage Orders") }
}

struct SellerReviewsView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @AppStorage("sellerSellerId") private var sellerId = ""
    @AppStorage("sellerBusinessName") private var sellerBusinessName = ""

    private var sellerProducts: [Product] {
        resolvedStorefrontProducts(
            remoteProducts: catalog.products,
            fallbackProducts: localProducts.products
        )
        .filter { product in
            sellerId.isEmpty || product.sellerId == sellerId
        }
    }

    private var reviewedProducts: [Product] {
        sellerProducts
            .filter { $0.reviewCount > 0 }
            .sorted {
                if $0.averageRating == $1.averageRating {
                    return $0.reviewCount > $1.reviewCount
                }
                return $0.averageRating > $1.averageRating
            }
    }

    private var totalReviewCount: Int {
        reviewedProducts.map(\.reviewCount).reduce(0, +)
    }

    private var weightedAverageRating: Double {
        guard totalReviewCount > 0 else { return 0 }
        let total = reviewedProducts.reduce(0.0) { partial, product in
            partial + (product.averageRating * Double(product.reviewCount))
        }
        return total / Double(totalReviewCount)
    }

    private var positiveReviewEstimate: Int {
        reviewedProducts
            .filter { $0.averageRating >= 4.0 }
            .map(\.reviewCount)
            .reduce(0, +)
    }

    private var sellerDisplayName: String {
        let trimmed = sellerBusinessName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let id = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? "Your store" : SellerProfile.fallbackDisplayName(forSellerId: id)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                SellerSettingsHeader(
                    title: "Reviews & Ratings",
                    subtitle: "Track buyer trust across \(sellerDisplayName)'s published product ratings."
                )

                summaryCard
                distributionCard
                reviewedProductsCard
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.top, TBTheme.spacingMD)
            .padding(.bottom, TBTheme.spacingXL)
        }
        .background(TBFrostBackground())
        .navigationTitle("Reviews")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await catalog.load()
        }
        .refreshable {
            await catalog.load()
        }
    }

    private var summaryCard: some View {
        SellerSettingsCard(title: "Rating Summary") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    reviewMetricCard(title: "Average", value: averageRatingText, subtitle: totalReviewCount == 0 ? "No reviews yet" : "Across reviewed products")
                    reviewMetricCard(title: "Reviews", value: "\(totalReviewCount)", subtitle: "Total buyer ratings")
                    reviewMetricCard(title: "Positive", value: "\(positiveReviewEstimate)", subtitle: "4 stars and above")
                }

                VStack(spacing: 12) {
                    reviewMetricCard(title: "Average", value: averageRatingText, subtitle: totalReviewCount == 0 ? "No reviews yet" : "Across reviewed products")
                    reviewMetricCard(title: "Reviews", value: "\(totalReviewCount)", subtitle: "Total buyer ratings")
                    reviewMetricCard(title: "Positive", value: "\(positiveReviewEstimate)", subtitle: "4 stars and above")
                }
            }

            Text("Ratings come from delivered orders and update as buyers leave product reviews.")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var distributionCard: some View {
        SellerSettingsCard(title: "Rating Distribution") {
            if totalReviewCount == 0 {
                emptyReviewsMessage
            } else {
                VStack(spacing: 10) {
                    ForEach((1...5).reversed(), id: \.self) { rating in
                        ratingDistributionRow(rating: rating, count: estimatedReviewCount(forRoundedRating: rating))
                    }
                }
            }
        }
    }

    private var reviewedProductsCard: some View {
        SellerSettingsCard(title: "Reviewed Products") {
            if reviewedProducts.isEmpty {
                emptyReviewsMessage
            } else {
                VStack(spacing: 10) {
                    ForEach(reviewedProducts) { product in
                        reviewedProductRow(product)
                    }
                }
            }
        }
    }

    private var emptyReviewsMessage: some View {
        Text("No buyer ratings yet. Once delivered orders receive reviews, they will appear here.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var averageRatingText: String {
        totalReviewCount == 0 ? "--" : String(format: "%.1f", weightedAverageRating)
    }

    private func reviewMetricCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.tbCaption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                if title == "Average", totalReviewCount > 0 {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TBTheme.accent)
                }
            }

            Text(subtitle)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
        )
    }

    private func ratingDistributionRow(rating: Int, count: Int) -> some View {
        let progress = totalReviewCount == 0 ? 0 : Double(count) / Double(totalReviewCount)

        return HStack(spacing: 10) {
            HStack(spacing: 3) {
                Text("\(rating)")
                    .font(.tbCaption)
                    .foregroundStyle(TBTheme.deepSky)
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TBTheme.accent)
            }
            .frame(width: 34, alignment: .leading)

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(TBTheme.skyLight.opacity(0.45))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(TBTheme.icyBlue.opacity(0.7))
                            .frame(width: max(4, proxy.size.width * progress))
                    }
            }
            .frame(height: 9)

            Text("\(count)")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func reviewedProductRow(_ product: Product) -> some View {
        HStack(alignment: .top, spacing: 12) {
            StorefrontImageView(reference: product.primaryImageReference) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TBTheme.skyLight.opacity(0.36))
                    .overlay {
                        Image(systemName: product.category.icon)
                            .foregroundStyle(TBTheme.icyBlue)
                    }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(product.name)
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Label(String(format: "%.1f", product.averageRating), systemImage: "star.fill")
                        .font(.tbCaption.weight(.semibold))
                        .foregroundStyle(TBTheme.accent)

                    Text("\(product.reviewCount) review\(product.reviewCount == 1 ? "" : "s")")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 0.8)
        )
    }

    private func estimatedReviewCount(forRoundedRating rating: Int) -> Int {
        reviewedProducts
            .filter { Int($0.averageRating.rounded()) == rating }
            .map(\.reviewCount)
            .reduce(0, +)
    }
}

struct ShippingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SellerShippingSettingsDraft.load()
    @State private var saveMessage: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                SellerSettingsHeader(
                    title: "Shipping Settings",
                    subtitle: "Set the timing, regions, and cost details buyers should see before checkout."
                )

                SellerSettingsCard(title: "Delivery Timing") {
                    SellerSettingsTextField(
                        title: "Processing time",
                        text: $draft.processingTime,
                        prompt: "1-2 business days"
                    )

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            SellerSettingsStepperField(title: "Min days", value: $draft.minShipDays, range: 1...14)
                            SellerSettingsStepperField(title: "Max days", value: $draft.maxShipDays, range: 1...21)
                        }

                        VStack(spacing: 12) {
                            SellerSettingsStepperField(title: "Min days", value: $draft.minShipDays, range: 1...14)
                            SellerSettingsStepperField(title: "Max days", value: $draft.maxShipDays, range: 1...21)
                        }
                    }
                }

                SellerSettingsCard(title: "Regions") {
                    SellerSettingsTextField(
                        title: "Primary shipping region",
                        text: $draft.primaryRegion,
                        prompt: "United States"
                    )

                    SellerSettingsToggleField(
                        title: "Offer international shipping",
                        subtitle: "Let buyers outside your main region request delivery.",
                        isOn: $draft.offersInternational
                    )

                    if draft.offersInternational {
                        SellerSettingsTextField(
                            title: "International regions",
                            text: $draft.internationalRegions,
                            prompt: "Canada, UK, EU"
                        )
                    }
                }

                SellerSettingsCard(title: "Rates") {
                    SellerSettingsTextField(
                        title: "Flat shipping rate",
                        text: $draft.flatRateText,
                        prompt: "4.99"
                    )
                    .keyboardType(.decimalPad)

                    SellerSettingsTextField(
                        title: "Free shipping threshold",
                        text: $draft.freeShippingThresholdText,
                        prompt: "35.00"
                    )
                    .keyboardType(.decimalPad)

                    SellerSettingsTextEditor(
                        title: "Shipping note",
                        text: $draft.shippingNote,
                        prompt: "Printed to order and packed in recyclable materials."
                    )
                }

                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.top, TBTheme.spacingMD)
            .padding(.bottom, 120)
        }
        .background(TBFrostBackground())
        .navigationTitle("Shipping Settings")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            SellerSettingsSaveBar(title: "Save Shipping Settings", action: saveSettings)
        }
    }

    private func saveSettings() {
        let minDays = min(draft.minShipDays, draft.maxShipDays)
        let maxDays = max(draft.minShipDays, draft.maxShipDays)
        draft.minShipDays = minDays
        draft.maxShipDays = maxDays
        draft.store()
        saveMessage = "Shipping settings saved locally."
    }
}

struct SellerPoliciesView: View {
    @State private var draft = SellerPolicySettingsDraft.load()
    @State private var saveMessage: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                SellerSettingsHeader(
                    title: "Policies",
                    subtitle: "Define the return, exchange, and cancellation rules shoppers should feel confident about."
                )

                SellerSettingsCard(title: "Returns & Exchanges") {
                    SellerSettingsToggleField(
                        title: "Accept returns",
                        subtitle: "Allow buyers to request a return after delivery.",
                        isOn: $draft.acceptsReturns
                    )

                    if draft.acceptsReturns {
                        SellerSettingsStepperField(title: "Return window", value: $draft.returnWindowDays, range: 3...30, suffix: "days")
                    }

                    SellerSettingsToggleField(
                        title: "Allow exchanges",
                        subtitle: "Let buyers exchange size, color, or replacement-ready items.",
                        isOn: $draft.allowsExchanges
                    )
                }

                SellerSettingsCard(title: "Cancellations") {
                    SellerSettingsToggleField(
                        title: "Allow order cancellations",
                        subtitle: "Give buyers a short grace period before production starts.",
                        isOn: $draft.allowsCancellations
                    )

                    if draft.allowsCancellations {
                        SellerSettingsStepperField(title: "Cancellation window", value: $draft.cancellationWindowHours, range: 1...48, suffix: "hrs")
                    }
                }

                SellerSettingsCard(title: "Policy Note") {
                    SellerSettingsTextEditor(
                        title: "Visible note",
                        text: $draft.policyNote,
                        prompt: "Custom printed items may vary slightly in finish, but every order is quality checked before it ships."
                    )
                }

                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.top, TBTheme.spacingMD)
            .padding(.bottom, 120)
        }
        .background(TBFrostBackground())
        .navigationTitle("Policies")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            SellerSettingsSaveBar(title: "Save Policies", action: savePolicies)
        }
    }

    private func savePolicies() {
        draft.store()
        saveMessage = "Policy settings saved locally."
    }
}

struct SupportView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                SellerSettingsHeader(
                    title: "Seller Support",
                    subtitle: "Get quick help with listings, payouts, shipping setup, and policy questions without leaving the seller flow."
                )

                SellerSettingsCard(title: "Quick Actions") {
                    supportActionButton(
                        title: "Email Seller Support",
                        subtitle: "Reach the team directly for account or listing questions.",
                        icon: "envelope.fill"
                    ) {
                        openURL(URL(string: "mailto:\(AppConstants.reportListingEmail)?subject=TenBelow%20Seller%20Support")!)
                    }

                    NavigationLink {
                        LegalDocumentView(document: .sellerAgreement)
                    } label: {
                        supportNavigationRow(
                            title: "View Seller Agreement",
                            subtitle: "Review marketplace expectations and seller terms.",
                            icon: "doc.text.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }

                SellerSettingsCard(title: "Helpful Links") {
                    NavigationLink {
                        LegalDocumentView(document: .exchangePolicy)
                    } label: {
                        supportLinkRow(title: "Exchange Policy", subtitle: "Buyer-facing exchange guidelines")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        InAppPolicyBrowser(url: AppConstants.ipPolicyURL)
                    } label: {
                        supportLinkRow(title: "IP Policy", subtitle: "Know what can and can’t be listed")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        LegalDocumentView(document: .dmcaPolicy)
                    } label: {
                        supportLinkRow(title: "DMCA", subtitle: "Report infringement or review copyright policy")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        LegalDocumentView(document: .privacyPolicy)
                    } label: {
                        supportLinkRow(title: "Privacy Policy", subtitle: "See how TenBelow handles seller data")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.top, TBTheme.spacingMD)
            .padding(.bottom, TBTheme.spacingXL)
        }
        .background(TBFrostBackground())
        .navigationTitle("Support")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func supportActionButton(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            supportNavigationRow(title: title, subtitle: subtitle, icon: icon, trailingSymbol: "arrow.up.right")
        }
        .buttonStyle(.plain)
    }

    private func supportNavigationRow(title: String, subtitle: String, icon: String, trailingSymbol: String = "chevron.right") -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TBTheme.icyBlue)
                .frame(width: 34, height: 34)
                .background(TBTheme.skyLight.opacity(0.35), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)

                Text(subtitle)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: trailingSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
        )
    }

    private func supportLinkRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.tbBodyStrong)
                    .foregroundStyle(TBTheme.deepSky)

                Text(subtitle)
                    .font(.tbCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct PayoutSettingsView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("sellerSellerId") private var sellerId = ""
    @AppStorage("sellerEmail") private var sellerEmail = ""
    @AppStorage("sellerPreviewMode") private var sellerPreviewMode = false
    @State private var status: SellerStatusResponse?
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var isLoadingStatus = false
    @State private var isOpeningStripe = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                SellerSettingsHeader(
                    title: "Payout Settings",
                    subtitle: "Check payout readiness and finish Stripe Connect when it is available."
                )

                if sellerPreviewMode {
                    SellerSettingsCard(title: "Preview Mode") {
                        Text("Stripe payout setup is unavailable while seller preview mode is active. Connect the live backend and sign in with a real seller account to finish onboarding.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                }

                SellerSettingsCard(title: "Stripe Account") {
                    stripeStatusRow(
                        title: "Seller ID",
                        value: sellerId.isEmpty ? "Not available" : sellerId
                    )
                    stripeStatusRow(
                        title: "Payout email",
                        value: sellerEmail.isEmpty ? "Not available" : sellerEmail
                    )
                    stripeStatusRow(
                        title: "Stripe account",
                        value: maskedStripeAccountId
                    )
                    stripeStatusRow(
                        title: "Setup availability",
                        value: status?.payoutSetupPending == true ? "Waiting on TenBelow" : "Available"
                    )
                    stripeStatusRow(
                        title: "Details submitted",
                        value: status?.detailsSubmitted == true ? "Complete" : "Pending"
                    )
                    stripeStatusRow(
                        title: "Charges",
                        value: status?.chargesEnabled == true ? "Enabled" : "Pending"
                    )
                    stripeStatusRow(
                        title: "Payouts",
                        value: status?.payoutsEnabled == true ? "Enabled" : "Pending"
                    )
                }

                SellerSettingsCard(title: "How It Works") {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TBTheme.icyBlue)

                        Text(howItWorksMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                }

                if let status {
                    SellerSettingsCard(title: "Payout Readiness") {
                        Text(payoutReadinessMessage(for: status))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                } else if !sellerPreviewMode {
                    SellerSettingsCard(title: "Status") {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(isLoadingStatus ? "Checking Stripe payout status..." : "Stripe payout status will appear here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let infoMessage {
                    Text(infoMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.top, TBTheme.spacingMD)
            .padding(.bottom, 120)
        }
        .background(TBFrostBackground())
        .navigationTitle("Payout")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await refreshStripeStatus()
        }
        .safeAreaInset(edge: .bottom) {
            payoutActionBar
        }
    }

    private var maskedStripeAccountId: String {
        guard let accountId = status?.stripeAccountId, !accountId.isEmpty else {
            return sellerPreviewMode ? "Preview account" : "Not connected yet"
        }
        if accountId.count <= 10 { return accountId }
        return "\(accountId.prefix(8))...\(accountId.suffix(4))"
    }

    @ViewBuilder
    private var payoutActionBar: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    if status?.onboardingComplete == true {
                        await openStripeDashboard()
                    } else {
                        await openStripeOnboarding()
                    }
                }
            } label: {
                Text(primaryActionTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [TBTheme.accent, TBTheme.deepSky],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isPrimaryActionEnabled)
            .opacity(isPrimaryActionEnabled ? 1 : 0.6)

            Button {
                Task { await refreshStripeStatus() }
            } label: {
                Text(isLoadingStatus ? "Refreshing..." : "Refresh payout status")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TBTheme.deepSky)
            }
            .buttonStyle(.plain)
            .disabled(isLoadingStatus)
        }
        .padding(.horizontal, TBTheme.spacingLG)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private var primaryActionTitle: String {
        if isOpeningStripe {
            return "Opening Stripe..."
        }
        if status?.payoutSetupPending == true {
            return "Stripe Setup Pending"
        }
        if status?.onboardingComplete == true {
            return "Open Stripe Dashboard"
        }
        return "Continue Stripe Payout Setup"
    }

    private var isPrimaryActionEnabled: Bool {
        !sellerPreviewMode
            && !sellerId.isEmpty
            && !isOpeningStripe
            && status != nil
            && status?.payoutSetupPending != true
    }

    private var howItWorksMessage: String {
        if status?.payoutSetupPending == true {
            return "Stripe Connect is not turned on for TenBelow yet. Your seller account can be created now, and this screen will unlock onboarding after the Stripe keys are added."
        }
        return "Bank account collection, identity verification, and payout dashboard access are handled in Stripe. TenBelow does not manage full banking details directly in this screen."
    }

    private func payoutReadinessMessage(for status: SellerStatusResponse) -> String {
        if status.payoutSetupPending {
            return status.payoutSetupMessage
                ?? "Stripe Connect is not configured yet. You can keep setting up your shop and return here when payouts are enabled."
        }
        if status.onboardingComplete {
            return "Your Stripe payout setup is complete. You can review transfers and payout timing in Stripe Express."
        }
        return "Your Stripe payout setup is not finished yet. Continue onboarding in Stripe to enable transfers from orders."
    }

    private func stripeStatusRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)
                .multilineTextAlignment(.trailing)
        }
    }

    private func refreshStripeStatus() async {
        guard !sellerPreviewMode, !sellerId.isEmpty else { return }

        await MainActor.run {
            isLoadingStatus = true
            errorMessage = nil
        }

        do {
            let refreshedStatus = try await SellerAPI.onboardingStatus(sellerId: sellerId)
            await MainActor.run {
                status = refreshedStatus
                infoMessage = nil
                isLoadingStatus = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoadingStatus = false
            }
        }
    }

    private func openStripeOnboarding() async {
        guard !sellerPreviewMode, !sellerId.isEmpty else { return }

        await MainActor.run {
            isOpeningStripe = true
            errorMessage = nil
        }

        defer {
            Task { @MainActor in
                isOpeningStripe = false
            }
        }

        do {
            let response = try await SellerAPI.onboardingLink(sellerId: sellerId)
            guard let url = URL(string: response.onboardingUrl) else {
                throw URLError(.badURL)
            }
            await MainActor.run {
                infoMessage = "Stripe opened in your browser. Come back here and tap refresh after finishing setup."
            }
            await MainActor.run {
                openURL(url)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openStripeDashboard() async {
        guard !sellerPreviewMode, !sellerId.isEmpty else { return }

        await MainActor.run {
            isOpeningStripe = true
            errorMessage = nil
        }

        defer {
            Task { @MainActor in
                isOpeningStripe = false
            }
        }

        do {
            let response = try await SellerAPI.dashboardLink(sellerId: sellerId)
            guard let url = URL(string: response.dashboardUrl) else {
                throw URLError(.badURL)
            }
            await MainActor.run {
                openURL(url)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct EditSellerProfileView: View {
    /// Same height as `PublicSellerProfileView.bannerHeader` so picked photos crop like the live storefront.
    private enum SellerProfileMedia {
        static let bannerPreviewHeight: CGFloat = 84
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalog: CatalogStore
    @AppStorage("catalogRefreshToken") private var catalogRefreshToken = 0
    @AppStorage("sellerBusinessName") private var storedBusinessName = ""
    @AppStorage("sellerSellerId") private var sessionSellerId = ""
    @Binding var seller: SellerProfile

    @State private var draft: SellerProfileDraft
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedBannerItem: PhotosPickerItem?
    @State private var selectedAvatarImage: UIImage?
    @State private var selectedBannerImage: UIImage?
    @State private var bannerZoom: CGFloat = 1
    @State private var bannerPan: CGSize = .zero
    @State private var bannerPreviewWidth: CGFloat = 0
    @State private var bannerEditSession = 0
    @State private var sellerServerSyncReady = true
    @State private var sellerSessionWarning: String?

    init(seller: Binding<SellerProfile>) {
        _seller = seller
        _draft = State(initialValue: SellerProfileDraft(seller: seller.wrappedValue))
    }

    #if os(iOS)
    private var activeScreenWidth: CGFloat? {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width
    }
    #endif

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                headerSection
                publicDetailsSection
                shopDetailsSection
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.top, TBTheme.spacingMD)
            .padding(.bottom, 120)
        }
        .background(TBFrostBackground())
        .navigationTitle("Edit Profile")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await refreshSellerSessionReadiness()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let sellerSessionWarning {
                    Text(sellerSessionWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        await saveProfile()
                    }
                } label: {
                    Text(isSaving ? "Saving..." : "Save Changes")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [TBTheme.accent, TBTheme.deepSky],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSaving || !sellerServerSyncReady)
                .opacity(isSaving || !sellerServerSyncReady ? 0.75 : 1)
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
        }
        .onChange(of: selectedAvatarItem) { _, item in
            Task { selectedAvatarImage = await loadProfileImage(from: item) }
        }
        .onChange(of: selectedBannerItem) { _, item in
            Task { selectedBannerImage = await loadProfileImage(from: item) }
        }
        .onChange(of: selectedBannerImage) { _, new in
            guard new != nil else { return }
            bannerZoom = 1
            bannerPan = .zero
            bannerEditSession += 1
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Make your storefront feel like you.")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)

            Text("Update the name, handle, bio, shipping timing, and details buyers see before they shop your products.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
    }

    private var publicDetailsSection: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                sectionTitle("Public Profile")

                profileMediaSection
                profileField("Shop name", text: $draft.displayName)
                profileField("Handle", text: $draft.handle, prefix: "@")
                profileField("Location", text: $draft.location)
                profileField("Website", text: $draft.website)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Bio")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $draft.bio)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Custom orders")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)

                    Toggle(isOn: $draft.acceptsCustomOrders) {
                        Text("Accept custom order requests")
                            .font(.tbBody)
                    }
                    .tint(TBTheme.deepSky)

                    Text("Buyers will see a small “Custom” action on your public storefront to describe a project and attach reference photos. You’ll get an email when email is configured on the server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    profileField(
                        "Custom order info link (optional)",
                        text: $draft.customOrderInfoURLString,
                        prompt: "https://example.com/custom-guidelines"
                    )
                }
            }
        }
    }

    private var profileMediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storefront images")
                .font(.tbCaption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                sellerBannerPreview

                if selectedBannerImage != nil {
                    Text("Pinch and drag on the banner to choose what buyers see.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PhotosPicker(selection: $selectedBannerItem, matching: .images, photoLibrary: .shared()) {
                    profileMediaButtonLabel(
                        title: selectedBannerImage == nil && draft.bannerURLString.isEmpty ? "Add banner" : "Update banner",
                        icon: "photo.fill.on.rectangle.fill"
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .center, spacing: 14) {
                sellerAvatarPreview

                PhotosPicker(selection: $selectedAvatarItem, matching: .images, photoLibrary: .shared()) {
                    profileMediaButtonLabel(
                        title: selectedAvatarImage == nil && draft.avatarURLString.isEmpty ? "Add photo" : "Update photo",
                        icon: "person.crop.circle.badge.plus"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sellerBannerPreview: some View {
        Group {
            if let selectedBannerImage {
                SellerBannerEditSlot(
                    image: selectedBannerImage,
                    slotHeight: SellerProfileMedia.bannerPreviewHeight,
                    zoom: $bannerZoom,
                    pan: $bannerPan,
                    reportedPreviewWidth: $bannerPreviewWidth
                )
                .id(bannerEditSession)
            } else {
                StorefrontImageView(reference: draft.bannerURLString, contentMode: .fill) {
                    LinearGradient(
                        colors: StorefrontBrandTheme.defaultBannerColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(height: SellerProfileMedia.bannerPreviewHeight)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: SellerProfileMedia.bannerPreviewHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.72), lineWidth: 1)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.08), radius: 10, y: 4)
    }

    private var sellerAvatarPreview: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)

            Group {
                if let selectedAvatarImage {
                    Image(uiImage: selectedAvatarImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    StorefrontImageView(reference: draft.avatarURLString, contentMode: .fill) {
                        Circle()
                            .fill(TBTheme.skyLight.opacity(0.9))
                            .overlay {
                                Text(avatarInitials)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(TBTheme.deepSky)
                            }
                    }
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(Circle())
        }
    }

    private var avatarInitials: String {
        let words = draft.displayName.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "TB" : letters.joined()
    }

    private func profileMediaButtonLabel(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.tbBodyStrong)
            Spacer(minLength: 8)
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(TBTheme.deepSky)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
        )
    }

    private var shopDetailsSection: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                sectionTitle("Seller Details")

                profileField("Processing time", text: $draft.processingTime)
                profileField("Materials", text: $draft.materials, prompt: "PLA+, PETG, Resin")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Shipping window")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            shippingStepper(title: "Min", value: $draft.shipsInMinDays, range: 1...14)
                            shippingStepper(title: "Max", value: $draft.shipsInMaxDays, range: 1...21)
                        }

                        VStack(spacing: 12) {
                            shippingStepper(title: "Min", value: $draft.shipsInMinDays, range: 1...14)
                            shippingStepper(title: "Max", value: $draft.shipsInMaxDays, range: 1...21)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(TBTheme.deepSky)
    }

    private func profileField(
        _ title: String,
        text: Binding<String>,
        prefix: String? = nil,
        prompt: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let prefix {
                    Text(prefix)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(TBTheme.icyBlue)
                }

                TextField(prompt ?? title, text: text)
                    .textInputAutocapitalization(prefix != nil || title == "Website" ? .never : .words)
                    .autocorrectionDisabled(prefix != nil || title == "Website")
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
            )
        }
    }

    private func shippingStepper(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.tbCaption)
                .foregroundStyle(.secondary)

            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue) day\(value.wrappedValue == 1 ? "" : "s")")
                    .font(.body.weight(.medium))
                    .foregroundStyle(TBTheme.deepSky)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshSellerSessionReadiness() async {
        do {
            try await MarketplaceAuthSession.ensureSellerSessionReady()
            sellerServerSyncReady = true
            sellerSessionWarning = nil
        } catch {
            sellerServerSyncReady = false
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                sellerSessionWarning = description
            } else {
                sellerSessionWarning = "Server sync is unavailable until you sign in as your seller account (Settings → Seller)."
            }
        }
    }

    private func saveProfile() async {
        let trimmedDisplayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = draft.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHandle = draft.normalizedHandle

        guard !trimmedDisplayName.isEmpty else {
            errorMessage = "Add a shop name so buyers can recognize your store."
            return
        }

        guard !normalizedHandle.isEmpty else {
            errorMessage = "Add a handle for your public storefront."
            return
        }

        guard !trimmedLocation.isEmpty else {
            errorMessage = "Add a location so shipping expectations feel clear."
            return
        }

        guard !trimmedBio.isEmpty else {
            errorMessage = "Add a short bio so buyers know what you make."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await MarketplaceAuthSession.ensureSellerSessionReady()
            sellerServerSyncReady = true
            sellerSessionWarning = nil
        } catch {
            sellerServerSyncReady = false
            sellerSessionWarning = profileSaveSyncFailureMessage(for: error)
            errorMessage = nil
            return
        }

        let normalizedSessionSellerId = sessionSellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedSessionSellerId.isEmpty, seller.id != normalizedSessionSellerId {
            errorMessage = "Your seller session doesn't match this storefront. Open Settings → Seller and sign in again."
            return
        }

        let minDays = min(draft.shipsInMinDays, draft.shipsInMaxDays)
        let maxDays = max(draft.shipsInMinDays, draft.shipsInMaxDays)
        let materials = draft.materialList.isEmpty ? seller.materials : draft.materialList
        let processingTime = draft.processingTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? seller.processingTime
            : draft.processingTime.trimmingCharacters(in: .whitespacesAndNewlines)

        let existingAvatarRef = [
            draft.avatarURLString,
            seller.avatarMediaReference ?? "",
            seller.avatarURL?.absoluteString ?? ""
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        let existingBannerRef = [
            draft.bannerURLString,
            seller.bannerMediaReference ?? "",
            seller.bannerURL?.absoluteString ?? ""
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        let uploadedAvatarURLString: String
        let uploadedBannerURLString: String
        do {
            uploadedAvatarURLString = try await uploadProfileImageIfNeeded(
                selectedAvatarImage,
                mediaKind: "avatar",
                fallbackURLString: existingAvatarRef,
                requireUpload: selectedAvatarImage != nil
            )
            let bannerUploadImage: UIImage? = {
                guard let selectedBannerImage else { return nil }
                let previewW: CGFloat = bannerPreviewWidth > 10
                    ? bannerPreviewWidth
                    : max((activeScreenWidth ?? 390) - TBTheme.spacingLG * 2, 320)
                let previewH = SellerProfileMedia.bannerPreviewHeight
                return SellerBannerCropExporter.renderForUpload(
                    image: selectedBannerImage,
                    previewContainerPoints: CGSize(width: previewW, height: previewH),
                    zoom: bannerZoom,
                    panPoints: bannerPan
                )
            }()
            uploadedBannerURLString = try await uploadProfileImageIfNeeded(
                bannerUploadImage,
                mediaKind: "banner",
                fallbackURLString: existingBannerRef,
                requireUpload: selectedBannerImage != nil
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't upload your storefront image. Check your connection and try again."
            return
        }

        let request = UpdateSellerProfileRequest(
            displayName: trimmedDisplayName,
            handle: "@\(normalizedHandle)",
            bio: trimmedBio,
            avatarURL: uploadedAvatarURLString.isEmpty ? nil : uploadedAvatarURLString,
            bannerURL: uploadedBannerURLString.isEmpty ? nil : uploadedBannerURLString,
            websiteURL: draft.normalizedWebsiteURL?.absoluteString,
            location: trimmedLocation,
            materials: materials,
            processingTime: processingTime,
            shipsInMinDays: minDays,
            shipsInMaxDays: maxDays,
            acceptsCustomOrders: draft.acceptsCustomOrders,
            customOrderInfoURL: draft.normalizedCustomOrderInfoURL?.absoluteString
        )

        #if DEBUG
        print("[ProfileSave] starting save sellerId=\(seller.id) avatar=\(uploadedAvatarURLString) banner=\(uploadedBannerURLString)")
        #endif

        do {
            let updatedSeller = try await SellerAPI.updateProfile(
                sellerId: seller.id,
                profile: request
            )
            applySavedSellerProfile(updatedSeller)
            #if DEBUG
            print("[ProfileSave] success sellerId=\(updatedSeller.id) avatar=\(updatedSeller.avatarURL?.absoluteString ?? "nil") banner=\(updatedSeller.bannerURL?.absoluteString ?? "nil") refreshToken=\(catalogRefreshToken)")
            #endif
            errorMessage = nil
            sellerSessionWarning = nil
            dismiss()
        } catch {
            if isSellerSessionFailure(error) {
                sellerServerSyncReady = false
                sellerSessionWarning = profileSaveSyncFailureMessage(for: error)
                errorMessage = nil
                return
            }

            let fallbackSeller = SellerProfile(
                id: seller.id,
                displayName: trimmedDisplayName,
                handle: "@\(normalizedHandle)",
                bio: trimmedBio,
                avatarMediaReference: uploadedAvatarURLString.isEmpty
                    ? seller.avatarMediaReference
                    : uploadedAvatarURLString,
                bannerMediaReference: uploadedBannerURLString.isEmpty
                    ? seller.bannerMediaReference
                    : uploadedBannerURLString,
                websiteURL: draft.normalizedWebsiteURL,
                location: trimmedLocation,
                shipsInDays: minDays...maxDays,
                materials: materials,
                processingTime: processingTime,
                productCount: seller.productCount,
                orderCount: seller.orderCount,
                rating: seller.rating,
                likeCount: seller.likeCount,
                pageViewCount: seller.pageViewCount,
                designLicense: seller.designLicense,
                isVerified: seller.isVerified,
                acceptsCustomOrders: draft.acceptsCustomOrders,
                customOrderInfoURL: draft.normalizedCustomOrderInfoURL,
                joinedAt: seller.joinedAt
            )
            applySavedSellerProfile(fallbackSeller)
            #if DEBUG
            print("[ProfileSave] fallback sellerId=\(fallbackSeller.id) avatar=\(fallbackSeller.avatarURL?.absoluteString ?? "nil") banner=\(fallbackSeller.bannerURL?.absoluteString ?? "nil") error=\((error as NSError).localizedDescription)")
            #endif
            // Local storefront updates immediately; keep a short sync note before dismiss.
            errorMessage = nil
            sellerSessionWarning = profileSaveSyncFailureMessage(for: error)
            dismiss()
        }
    }

    private func applySavedSellerProfile(_ updatedSeller: SellerProfile) {
        seller = updatedSeller
        storedBusinessName = updatedSeller.displayName
        draft.avatarURLString = updatedSeller.avatarMediaReference
            ?? updatedSeller.avatarURL?.absoluteString
            ?? draft.avatarURLString
        draft.bannerURLString = updatedSeller.bannerMediaReference
            ?? updatedSeller.bannerURL?.absoluteString
            ?? draft.bannerURLString
        updatedSeller.storeLocally()
        catalog.upsertSellerProfile(updatedSeller)
        catalogRefreshToken += 1
        selectedAvatarImage = nil
        selectedBannerImage = nil
        selectedAvatarItem = nil
        selectedBannerItem = nil
    }

    private func loadProfileImage(from item: PhotosPickerItem?) async -> UIImage? {
        guard let item else { return nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        #if os(iOS)
        return UIImage(data: data)
        #else
        return nil
        #endif
    }

    private func uploadProfileImageIfNeeded(
        _ image: UIImage?,
        mediaKind: String,
        fallbackURLString: String,
        requireUpload: Bool
    ) async throws -> String {
        guard let image else {
            return fallbackURLString
        }
        guard let imageData = image.jpegData(compressionQuality: 0.84) else {
            if requireUpload {
                throw ProfileMediaUploadError.invalidImage(mediaKind)
            }
            return fallbackURLString
        }

        do {
            return try await SellerAPI.uploadMedia(
                sellerId: seller.id,
                productId: "profile",
                mediaKind: mediaKind,
                slot: "0",
                fileExtension: "jpg",
                contentType: "image/jpeg",
                data: imageData
            )
        } catch {
            if requireUpload {
                if let apiError = error as? SellerAPIError, !apiError.message.isEmpty {
                    throw apiError
                }
                throw ProfileMediaUploadError.uploadFailed(mediaKind)
            }
            return fallbackURLString
        }
    }
}

private enum ProfileMediaUploadError: LocalizedError {
    case invalidImage(String)
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage(let kind):
            return "That \(kind == "banner" ? "banner" : "photo") couldn't be prepared. Try another image."
        case .uploadFailed(let kind):
            return "Couldn't upload your \(kind == "banner" ? "banner" : "profile photo"). Check your connection and try Save again."
        }
    }
}

private func profileSaveSyncFailureMessage(for error: Error) -> String {
    let detail: String = {
        if let apiError = error as? SellerAPIError {
            return apiError.message
        }
        return (error as NSError).localizedDescription
    }()
    let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmedDetail.lowercased()

    if let apiError = error as? SellerAPIError, apiError.isSellerSessionRequired {
        return """
        Server sync is locked until this phone signs in as your seller account. \
        Open Settings → switch to Seller (or sign in again with your seller email), then return here and save.
        """
    }

    if lower.contains("authenticated seller session required") || lower.contains("seller session") {
        return """
        Server sync is locked until this phone signs in as your seller account. \
        Open Settings → switch to Seller (or sign in again with your seller email), then return here and save.
        """
    }

    if trimmedDetail.isEmpty || trimmedDetail == "The operation couldn’t be completed." {
        return "Saved on this device. Server sync failed, so other devices will not see it yet. Check that you’re in Seller mode and online."
    }

    return "Saved on this device. Server sync failed: \(trimmedDetail)"
}

private func isSellerSessionFailure(_ error: Error) -> Bool {
    if let apiError = error as? SellerAPIError, apiError.isSellerSessionRequired {
        return true
    }

    if error is MarketplaceAuthSessionError {
        return true
    }

    let description = (error as NSError).localizedDescription.lowercased()
    return description.contains("authenticated seller session required") || description.contains("seller session")
}

private struct SellerProfileDraft {
    var displayName: String
    var handle: String
    var bio: String
    var location: String
    var website: String
    var processingTime: String
    var materials: String
    var shipsInMinDays: Int
    var shipsInMaxDays: Int
    var avatarURLString: String
    var bannerURLString: String
    var acceptsCustomOrders: Bool
    var customOrderInfoURLString: String

    init(seller: SellerProfile) {
        displayName = seller.displayName
        handle = seller.handle.replacingOccurrences(of: "@", with: "")
        bio = seller.bio
        location = seller.location
        website = seller.websiteURL?.absoluteString ?? ""
        processingTime = seller.processingTime
        materials = seller.materials.joined(separator: ", ")
        shipsInMinDays = seller.shipsInDays.lowerBound
        shipsInMaxDays = seller.shipsInDays.upperBound
        // Prefer raw hosted references (`/media/...`) so saves keep working after relaunch.
        avatarURLString = seller.avatarMediaReference
            ?? seller.avatarURL?.absoluteString
            ?? ""
        bannerURLString = seller.bannerMediaReference
            ?? seller.bannerURL?.absoluteString
            ?? ""
        acceptsCustomOrders = seller.acceptsCustomOrders
        customOrderInfoURLString = seller.customOrderInfoURL?.absoluteString ?? ""
    }

    var normalizedHandle: String {
        handle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    var normalizedWebsiteURL: URL? {
        let trimmedWebsite = website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWebsite.isEmpty else { return nil }

        if let directURL = URL(string: trimmedWebsite), directURL.scheme != nil {
            return directURL
        }

        return URL(string: "https://\(trimmedWebsite)")
    }

    var normalizedCustomOrderInfoURL: URL? {
        let trimmed = customOrderInfoURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let directURL = URL(string: trimmed), directURL.scheme != nil {
            return directURL
        }

        return URL(string: "https://\(trimmed)")
    }

    var materialList: [String] {
        materials
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct SellerSettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SellerSettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)
                .fixedSize(horizontal: false, vertical: true)

            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.035), radius: 8, y: 4)
    }
}

private struct SellerSettingsTextField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    private var keyboard: UIKeyboardType = .default

    init(title: String, text: Binding<String>, prompt: String) {
        self.title = title
        _text = text
        self.prompt = prompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.tbCaption)
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
                )
        }
    }

    func keyboardType(_ keyboard: UIKeyboardType) -> SellerSettingsTextField {
        var copy = self
        copy.keyboard = keyboard
        return copy
    }
}

private struct SellerSettingsTextEditor: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(prompt)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 20)
                }

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(10)
            }
            .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
            )
        }
    }
}

private struct SellerSettingsToggleField: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TBTheme.deepSky)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(TBTheme.icyBlue)
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct SellerSettingsStepperField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix: String = "days"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Stepper(value: $value, in: range) {
                Text(valueLabel)
                    .font(.body.weight(.medium))
                    .foregroundStyle(TBTheme.deepSky)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 78, alignment: .leading)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueLabel: String {
        switch suffix {
        case "days":
            return "\(value) day\(value == 1 ? "" : "s")"
        case "hrs":
            return "\(value) hr\(value == 1 ? "" : "s")"
        default:
            return "\(value) \(suffix)"
        }
    }
}

private struct SellerSettingsSaveBar: View {
    let title: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                Text(title)
                    .font(.headline)
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
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }
}

private enum SellerSettingsStorageKey {
    static let shipping = "sellerShippingSettingsData"
    static let policies = "sellerPolicySettingsData"
}

private struct SellerShippingSettingsDraft: Codable {
    var processingTime: String
    var minShipDays: Int
    var maxShipDays: Int
    var primaryRegion: String
    var offersInternational: Bool
    var internationalRegions: String
    var flatRateText: String
    var freeShippingThresholdText: String
    var shippingNote: String

    static func load() -> SellerShippingSettingsDraft {
        if let data = UserDefaults.standard.data(forKey: SellerSettingsStorageKey.shipping),
           let saved = try? JSONDecoder().decode(SellerShippingSettingsDraft.self, from: data) {
            return saved
        }

        return SellerShippingSettingsDraft(
            processingTime: "1-2 business days",
            minShipDays: 2,
            maxShipDays: 4,
            primaryRegion: "United States",
            offersInternational: false,
            internationalRegions: "",
            flatRateText: "4.99",
            freeShippingThresholdText: "35.00",
            shippingNote: "Orders are printed to order and packed with care."
        )
    }

    func store() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: SellerSettingsStorageKey.shipping)
    }
}

private struct SellerPolicySettingsDraft: Codable {
    var acceptsReturns: Bool
    var returnWindowDays: Int
    var allowsExchanges: Bool
    var allowsCancellations: Bool
    var cancellationWindowHours: Int
    var policyNote: String

    static func load() -> SellerPolicySettingsDraft {
        if let data = UserDefaults.standard.data(forKey: SellerSettingsStorageKey.policies),
           let saved = try? JSONDecoder().decode(SellerPolicySettingsDraft.self, from: data) {
            return saved
        }

        return SellerPolicySettingsDraft(
            acceptsReturns: true,
            returnWindowDays: 14,
            allowsExchanges: true,
            allowsCancellations: true,
            cancellationWindowHours: 12,
            policyNote: "Because each product is made to order, custom color requests and personalized pieces may be final sale."
        )
    }

    func store() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: SellerSettingsStorageKey.policies)
    }
}

private enum SellerProductDraftStorage {
    static func key(for sellerId: String) -> String {
        "sellerProductDraftsData.\(sellerId)"
    }
}

private enum SellerDeletedProductStorage {
    static func key(for sellerId: String) -> String {
        "sellerDeletedProductIDs.\(sellerId)"
    }

    static func load(for sellerId: String) -> Set<String> {
        guard let saved = UserDefaults.standard.array(forKey: key(for: sellerId)) as? [String] else {
            return []
        }
        return Set(saved)
    }

    static func store(_ productIDs: Set<String>, for sellerId: String) {
        UserDefaults.standard.set(Array(productIDs).sorted(), forKey: key(for: sellerId))
    }
}

struct ProductRightsOwnershipSection: View {
    @Binding var ownershipType: String?
    @Binding var referenceFlags: [String]
    @Binding var certificationAccepted: Bool
    @Binding var certificationAcceptedAt: Date?
    var showIncompleteMessage = false

    var body: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Product Rights & Ownership")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)

                    Text("Before submitting, confirm that you have the legal right to sell this product on TenBelow.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("How do you have the right to sell this product?")
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)

                    ForEach(ProductRightsOwnershipOption.allCases) { option in
                        rightsChoiceRow(
                            title: option.rawValue,
                            isSelected: ownershipType == option.rawValue,
                            systemImage: ownershipType == option.rawValue ? "largecircle.fill.circle" : "circle"
                        ) {
                            ownershipType = option.rawValue
                        }
                    }
                }

                Divider()
                    .overlay(TBTheme.skyBlue.opacity(0.10))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Does this product contain or reference any of the following?")
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)

                    ForEach(ProductRightsReferenceFlag.allCases) { flag in
                        rightsChoiceRow(
                            title: flag.rawValue,
                            isSelected: referenceFlags.contains(flag.rawValue),
                            systemImage: referenceFlags.contains(flag.rawValue) ? "checkmark.circle.fill" : "circle"
                        ) {
                            toggleReferenceFlag(flag)
                        }
                    }
                }

                Button {
                    certificationAccepted.toggle()
                    certificationAcceptedAt = certificationAccepted ? (certificationAcceptedAt ?? Date()) : nil
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: certificationAccepted ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(certificationAccepted ? TBTheme.deepSky : Color.secondary)
                            .padding(.top, 1)

                        Text("I certify that the information above is true and accurate. I understand that uploading copyrighted, trademarked, counterfeit, unsafe, or unauthorized products may result in listing removal, account suspension, payout holds, account termination, and potential legal action by third-party rights holders.")
                            .font(.tbCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                if showIncompleteMessage {
                    Text("Complete this section before submitting your product.")
                        .font(.tbCaption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func rightsChoiceRow(
        title: String,
        isSelected: Bool,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? TBTheme.deepSky : Color.secondary)

                Text(title)
                    .font(.tbBody)
                    .foregroundStyle(.primary.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color.white.opacity(isSelected ? 0.82 : 0.56), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? TBTheme.skyBlue.opacity(0.30) : TBTheme.skyBlue.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleReferenceFlag(_ flag: ProductRightsReferenceFlag) {
        if flag == .noneOfTheAbove {
            referenceFlags = referenceFlags.contains(flag.rawValue) ? [] : [flag.rawValue]
            return
        }

        var updated = referenceFlags.filter { $0 != ProductRightsReferenceFlag.noneOfTheAbove.rawValue }
        if updated.contains(flag.rawValue) {
            updated.removeAll { $0 == flag.rawValue }
        } else {
            updated.append(flag.rawValue)
        }
        referenceFlags = updated
    }
}

private extension SellerProductDraft {
    static func load(for sellerId: String, fallbackProducts: [Product]) -> [SellerProductDraft] {
        if let data = UserDefaults.standard.data(forKey: SellerProductDraftStorage.key(for: sellerId)),
           let saved = try? JSONDecoder().decode([SellerProductDraft].self, from: data) {
            return saved
        }

        return fallbackProducts
            .filter { $0.sellerId == sellerId }
            .map { product in
                SellerProductDraft(
                    id: product.id,
                    sellerId: product.sellerId,
                    name: product.name,
                    priceText: String(format: "%.2f", Double(product.priceCents) / 100.0),
                    category: product.category,
                    imageURLStrings: product.imageNames,
                    demoVideoURLString: product.demoVideoURL?.absoluteString ?? "",
                    material: product.material,
                    productionNote: product.productionNote,
                    durabilityNote: product.durabilityNote,
                    careWarningsText: product.careWarnings.joined(separator: "\n"),
                    shipsInMinDays: product.shipsInDays.lowerBound,
                    shipsInMaxDays: product.shipsInDays.upperBound,
                    productionPreviewURLString: product.productionPreviewURL?.absoluteString ?? "",
                    marketplaceStatusRaw: SellerMarketplaceStatus.live.rawValue,
                    serverReviewNotes: nil
                )
            }
    }

    static func store(_ drafts: [SellerProductDraft], for sellerId: String) {
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        UserDefaults.standard.set(data, forKey: SellerProductDraftStorage.key(for: sellerId))
    }
}

private extension Product {
    init(draft: SellerProductDraft, fallbackImageNames: [String]) {
        self.init(
            id: draft.id,
            sellerId: draft.sellerId,
            name: draft.name.isEmpty ? "Untitled Product" : draft.name,
            priceCents: max(draft.priceCents, 0),
            category: draft.category,
            imageNames: draft.imageURLStrings.isEmpty ? fallbackImageNames : draft.imageURLStrings,
            demoVideoURL: URL(string: draft.demoVideoURLString),
            productionPreviewURL: URL(string: draft.productionPreviewURLString),
            pageViewCount: 0,
            favoriteCount: 0,
            material: draft.material.isEmpty ? "PLA+" : draft.material,
            productionNote: draft.productionNote,
            durabilityNote: draft.durabilityNote.isEmpty ? "Built for everyday use." : draft.durabilityNote,
            careWarnings: draft.warningLines.isEmpty ? ["Handle with care."] : draft.warningLines,
            shipsInDays: draft.shipsInMinDays...draft.shipsInMaxDays,
            rightsOwnershipType: draft.rightsOwnershipType,
            rightsReferenceFlags: draft.rightsReferenceFlags,
            rightsCertificationAccepted: draft.rightsCertificationAccepted,
            rightsCertificationAcceptedAt: draft.rightsCertificationAcceptedAt,
            requiresManualReview: draft.requiresManualReview,
            reviewReason: draft.reviewReason
        )
    }
}
