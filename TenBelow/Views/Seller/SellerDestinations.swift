import SwiftUI
import PhotosUI
import AVKit
#if os(iOS)
import UIKit
#endif

struct AddProductView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onSave: (SellerProductDraft, SellerProductMediaSelection) -> Void

    @State private var draft: SellerProductDraft
    @State private var selectedImageItems: [PhotosPickerItem] = []
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedProductionPreviewItem: PhotosPickerItem?
    @State private var selectedImages: [UIImage] = []
    @State private var selectedVideoURL: URL?
    @State private var selectedProductionPreviewURL: URL?
    @State private var isShowingVideoPreview = false
    @State private var isShowingProductionPreview = false
    @State private var mediaErrorMessage: String?

    init(
        title: String = "Add Product",
        initialDraft: SellerProductDraft = .new(),
        onSave: @escaping (SellerProductDraft, SellerProductMediaSelection) -> Void = { _, _ in }
    ) {
        self.title = title
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draft.priceCents > 0 &&
        !draft.material.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.productionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.durabilityNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.warningLines.isEmpty &&
        draft.shipsInMaxDays >= draft.shipsInMinDays
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TBTheme.spacingXL) {
                headerSection
                basicInfoSection
                detailsSection
                mediaSection
                saveSection
            }
            .padding(TBTheme.spacingLG)
        }
        .background(TBTheme.cloudWhite.ignoresSafeArea())
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
                VideoPlayer(player: AVPlayer(url: selectedVideoURL))
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $isShowingProductionPreview) {
            if let selectedProductionPreviewURL {
                VideoPlayer(player: AVPlayer(url: selectedProductionPreviewURL))
                    .ignoresSafeArea()
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

                Text("Add up to 6 photos and one short product clip.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                if let mediaErrorMessage {
                    Text(mediaErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                PhotosPicker(
                    selection: $selectedImageItems,
                    maxSelectionCount: 6,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    mediaPickerButtonLabel(
                        title: selectedImages.isEmpty && draft.imageURLStrings.isEmpty ? "Add Photos" : "Update Photos",
                        icon: "photo.on.rectangle.angled"
                    )
                }
                .buttonStyle(.plain)

                if !selectedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(selectedImages.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 108, height: 108)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                                    )
                                    .shadow(color: TBTheme.deepSky.opacity(0.08), radius: 8, y: 4)
                            }
                        }
                    }
                } else if !draft.imageURLStrings.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(draft.imageURLStrings, id: \.self) { reference in
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
                            }
                        }
                    }
                }

                PhotosPicker(
                    selection: $selectedVideoItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    mediaPickerButtonLabel(
                        title: selectedVideoURL == nil ? "Add Short Clip" : "Replace Short Clip",
                        icon: "video.badge.plus"
                    )
                }
                .buttonStyle(.plain)

                if let selectedVideoURL {
                    HStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(TBTheme.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Short product clip ready")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(TBTheme.deepSky)
                                Text(selectedVideoURL.lastPathComponent)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Button("Preview") {
                            isShowingVideoPreview = true
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.accent)
                        .buttonStyle(.plain)

                        Button("Remove") {
                            clearSelectedVideo()
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
                    )
                }

                Divider()
                    .overlay(TBTheme.skyBlue.opacity(0.10))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Production Preview (Orders only)")
                        .font(.tbBodyStrong)
                        .foregroundStyle(TBTheme.deepSky)

                    Text("Optional private clip shown in Order Details after production begins. Not visible in the public gallery.")
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
                        title: selectedProductionPreviewURL == nil ? "Add Production Preview" : "Replace Production Preview",
                        icon: "sparkles.tv"
                    )
                }
                .buttonStyle(.plain)

                if let selectedProductionPreviewURL {
                    HStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles.tv")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(TBTheme.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Production preview ready")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(TBTheme.deepSky)
                                Text(selectedProductionPreviewURL.lastPathComponent)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Button("Preview") {
                            isShowingProductionPreview = true
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.accent)
                        .buttonStyle(.plain)

                        Button("Remove") {
                            clearSelectedProductionPreview()
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
                    )
                }
            }
        }
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                var updatedDraft = draft
                updatedDraft.demoVideoURLString = selectedVideoURL?.absoluteString ?? draft.demoVideoURLString
                updatedDraft.productionPreviewURLString = selectedProductionPreviewURL?.absoluteString ?? ""
                draft = updatedDraft
                onSave(
                    updatedDraft,
                    SellerProductMediaSelection(
                        selectedImages: selectedImages,
                        selectedVideoURL: selectedVideoURL
                    )
                )
                dismiss()
            } label: {
                Text(title == "Add Product" ? "Save Product Draft" : "Update Product Details")
                    .font(.tbHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(PrimaryCTAButtonStyle())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.6)

            Text("This editor controls title, price, details, shipping, and media for the product page.")
                .font(.tbCaption)
                .foregroundStyle(.secondary)
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

    private func mediaPickerButtonLabel(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
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

    private func loadSelectedImages(from items: [PhotosPickerItem]) async {
        var loadedImages: [UIImage] = []

        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loadedImages.append(image)
            }
        }

        await MainActor.run {
            selectedImages = loadedImages
        }
    }

    private func loadSelectedVideo(from item: PhotosPickerItem?) async {
        guard let item else {
            await MainActor.run { selectedVideoURL = nil }
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
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
                selectedVideoURL = outputURL
            }
        } catch {
            await MainActor.run {
                mediaErrorMessage = "We couldn't load that video clip."
            }
        }
    }

    private func loadSelectedProductionPreview(from item: PhotosPickerItem?) async {
        guard let item else {
            await MainActor.run { selectedProductionPreviewURL = nil }
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
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
                selectedProductionPreviewURL = outputURL
            }
        } catch {
            await MainActor.run {
                mediaErrorMessage = "We couldn't load that production preview clip."
            }
        }
    }

    private func clearSelectedVideo() {
        if let selectedVideoURL {
            try? FileManager.default.removeItem(at: selectedVideoURL)
        }

        selectedVideoURL = nil
        selectedVideoItem = nil
    }

    private func clearSelectedProductionPreview() {
        if let selectedProductionPreviewURL {
            try? FileManager.default.removeItem(at: selectedProductionPreviewURL)
        }

        selectedProductionPreviewURL = nil
        selectedProductionPreviewItem = nil
    }
}

struct SellerProductMediaSelection {
    let selectedImages: [UIImage]
    let selectedVideoURL: URL?
}

struct SellerProductsView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var localProducts: LocalProductStore
    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore
    @AppStorage("catalogRefreshToken") private var catalogRefreshToken = 0

    let seller: SellerProfile
    let products: [Product]
    let startInAddMode: Bool

    @State private var productDrafts: [SellerProductDraft]
    @State private var selectedDraft: SellerProductDraft?
    @State private var isShowingAddSheet = false
    @State private var isShowingSubscriptionSheet = false
    @State private var hasPresentedInitialAdd = false
    @State private var syncMessage: String?

    init(
        seller: SellerProfile = .sample,
        products: [Product] = MockData.products,
        startInAddMode: Bool = false
    ) {
        self.seller = seller
        self.products = products
        self.startInAddMode = startInAddMode
        _productDrafts = State(
            initialValue: SellerProductDraft.load(for: seller.id, fallbackProducts: products)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                headerCard
                inventorySnapshotCard

                if let syncMessage {
                    Text(syncMessage)
                        .font(.tbCaption)
                        .foregroundStyle(syncMessage.contains("device") ? .orange : .green)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(productDrafts) { draft in
                    Button {
                        if sellerSubscription.hasActiveSubscription {
                            selectedDraft = draft
                        } else {
                            isShowingSubscriptionSheet = true
                        }
                    } label: {
                        sellerProductCard(draft)
                    }
                    .buttonStyle(.plain)
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
        .background(TBTheme.cloudWhite.ignoresSafeArea())
        .navigationTitle("My Products")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if sellerSubscription.hasActiveSubscription {
                        isShowingAddSheet = true
                    } else {
                        isShowingSubscriptionSheet = true
                    }
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
                    productDrafts.insert(savedDraft, at: 0)
                    persistDrafts()
                    localProducts.saveDraft(savedDraft)
                    Task {
                        await syncDraftToServer(savedDraft, mediaSelection: mediaSelection)
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingSubscriptionSheet) {
            SellerSubscriptionView()
        }
        .sheet(item: $selectedDraft) { draft in
            NavigationStack {
                AddProductView(
                    title: "Edit Product",
                    initialDraft: draft
                ) { updatedDraft, mediaSelection in
                    if let index = productDrafts.firstIndex(where: { $0.id == updatedDraft.id }) {
                        productDrafts[index] = updatedDraft
                    } else {
                        productDrafts.insert(updatedDraft, at: 0)
                    }
                    persistDrafts()
                    localProducts.saveDraft(updatedDraft)
                    Task {
                        await syncDraftToServer(updatedDraft, mediaSelection: mediaSelection)
                    }
                }
            }
        }
        .onAppear {
            guard startInAddMode, !hasPresentedInitialAdd else { return }
            hasPresentedInitialAdd = true
            if sellerSubscription.hasActiveSubscription {
                isShowingAddSheet = true
            } else {
                isShowingSubscriptionSheet = true
            }
        }
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
                        title: "Avg Price",
                        value: averagePriceText,
                        subtitle: "Across saved drafts"
                    )
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

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(draft.productionNote)
                .font(.tbCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 10) {
                sellerMetaPill(draft.category.rawValue)
                sellerMetaPill(draft.material)
                sellerMetaPill("\(draft.shipsInMinDays)-\(draft.shipsInMaxDays) days")
            }
        }
        .padding(16)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.03), radius: 10, y: 5)
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

    private var averagePriceText: String {
        guard !productDrafts.isEmpty else { return "$0" }
        let average = productDrafts.map(\.priceCents).reduce(0, +) / max(productDrafts.count, 1)
        return Money.format(cents: average)
    }

    private func persistDrafts() {
        SellerProductDraft.store(productDrafts, for: seller.id)
    }

    private func syncDraftToServer(
        _ draft: SellerProductDraft,
        mediaSelection: SellerProductMediaSelection
    ) async {
        let fallbackProduct = products.first(where: { $0.id == draft.id })
            ?? localProducts.product(withId: draft.id)
        let uploadedImageURLStrings = await uploadImagesIfNeeded(
            mediaSelection.selectedImages,
            draft: draft,
            fallbackURLs: draft.imageURLStrings
        )
        let uploadedDemoVideoURLString = await uploadVideoIfNeeded(
            mediaSelection.selectedVideoURL,
            draft: draft,
            fallbackURLString: draft.demoVideoURLString
        )
        var syncedDraft = draft
        syncedDraft.imageURLStrings = uploadedImageURLStrings
        syncedDraft.demoVideoURLString = uploadedDemoVideoURLString
        let request = UpsertSellerProductRequest(
            name: syncedDraft.name.isEmpty ? "Untitled Product" : syncedDraft.name,
            priceCents: max(syncedDraft.priceCents, 0),
            category: syncedDraft.category.rawValue,
            imageURLs: uploadedImageURLStrings.isEmpty ? (fallbackProduct?.imageNames ?? []) : uploadedImageURLStrings,
            demoVideoURL: uploadedDemoVideoURLString.isEmpty ? fallbackProduct?.demoVideoURL?.absoluteString : uploadedDemoVideoURLString,
            material: syncedDraft.material.isEmpty ? "PLA+" : syncedDraft.material,
            durabilityNote: syncedDraft.durabilityNote.isEmpty ? "Built for everyday use." : syncedDraft.durabilityNote,
            careWarnings: syncedDraft.warningLines.isEmpty ? ["Handle with care."] : syncedDraft.warningLines,
            shipsInMinDays: min(syncedDraft.shipsInMinDays, syncedDraft.shipsInMaxDays),
            shipsInMaxDays: max(syncedDraft.shipsInMinDays, syncedDraft.shipsInMaxDays),
            isDrop: false,
            isActive: true,
            isApproved: true
        )

        do {
            let remoteProduct = try await SellerAPI.upsertProduct(
                sellerId: seller.id,
                productId: draft.id,
                product: request
            )
            await MainActor.run {
                if let index = productDrafts.firstIndex(where: { $0.id == draft.id }) {
                    productDrafts[index] = syncedDraft
                }
                persistDrafts()
                localProducts.saveDraft(syncedDraft)
                catalog.upsertRemoteProduct(remoteProduct)
                catalogRefreshToken += 1
                syncMessage = "Saved and synced to your live store."
            }
        } catch {
            await MainActor.run {
                syncMessage = "Saved on this device. Live store sync failed for now."
            }
        }
    }

    private func uploadImagesIfNeeded(
        _ selectedImages: [UIImage],
        draft: SellerProductDraft,
        fallbackURLs: [String]
    ) async -> [String] {
        guard !selectedImages.isEmpty else { return fallbackURLs }

        var uploadedURLs: [String] = []
        for (index, image) in selectedImages.enumerated() {
            guard let imageData = image.jpegData(compressionQuality: 0.84) else { continue }
            do {
                let url = try await SellerAPI.uploadMedia(
                    sellerId: seller.id,
                    productId: draft.id,
                    mediaKind: "image",
                    slot: "\(index)",
                    fileExtension: "jpg",
                    contentType: "image/jpeg",
                    data: imageData
                )
                uploadedURLs.append(url)
            } catch {
                return fallbackURLs
            }
        }
        return uploadedURLs.isEmpty ? fallbackURLs : uploadedURLs
    }

    private func uploadVideoIfNeeded(
        _ selectedVideoURL: URL?,
        draft: SellerProductDraft,
        fallbackURLString: String
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
                mediaKind: "demo-video",
                slot: "0",
                fileExtension: fileExtension,
                contentType: "video/\(fileExtension == "mp4" ? "mp4" : "quicktime")",
                data: videoData
            )
        } catch {
            return fallbackURLString.isEmpty ? selectedVideoURL.absoluteString : fallbackURLString
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
            productionPreviewURLString: ""
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
        productionPreviewURLString: String
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
}

struct SellerStorePreviewView: View {
    var seller: SellerProfile?
    var products: [Product] = []

    var body: some View {
        if let seller {
            PublicSellerProfileView(
                seller: seller,
                products: previewDisplayProducts,
                previewDraftIDs: previewDraftIDs,
                showsDraftPreviewBanner: showsDraftPreviewBanner
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

    private var showsDraftPreviewBanner: Bool {
        !localDrafts.isEmpty
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
    var body: some View { Text("Reviews").navigationTitle("Reviews") }
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
        .background(TBTheme.cloudWhite.ignoresSafeArea())
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
        .background(TBTheme.cloudWhite.ignoresSafeArea())
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

                    supportActionButton(
                        title: "View Seller Agreement",
                        subtitle: "Review marketplace expectations and seller terms.",
                        icon: "doc.text.fill"
                    ) {
                        openURL(AppConstants.sellerAgreementURL)
                    }
                }

                SellerSettingsCard(title: "Helpful Links") {
                    supportLinkRow(title: "Exchange Policy", subtitle: "Buyer-facing exchange guidelines", url: AppConstants.exchangePolicyURL)
                    supportLinkRow(title: "IP Policy", subtitle: "Know what can and can’t be listed", url: AppConstants.ipPolicyURL)
                    supportLinkRow(title: "DMCA", subtitle: "Report infringement or review copyright policy", url: AppConstants.dmcaURL)
                    supportLinkRow(title: "Privacy Policy", subtitle: "See how TenBelow handles seller data", url: AppConstants.privacyPolicyURL)
                }

                SellerSettingsCard(title: "Seller FAQ") {
                    faqRow(question: "When do I need to handle subscription setup?", answer: "You can wait until you begin uploading products. The app will remind you again before you publish.")
                    faqRow(question: "What should I include in my shipping settings?", answer: "Set your real processing time, main shipping region, and any rate notes so buyers understand delivery expectations before checkout.")
                    faqRow(question: "How should I write product policies?", answer: "Keep them short and specific. Tell buyers whether returns, exchanges, and cancellations are accepted and note anything custom-made that may be final sale.")
                }
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.top, TBTheme.spacingMD)
            .padding(.bottom, TBTheme.spacingXL)
        }
        .background(TBTheme.cloudWhite.ignoresSafeArea())
        .navigationTitle("Support")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func supportActionButton(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

                Image(systemName: "arrow.up.right")
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
        .buttonStyle(.plain)
    }

    private func supportLinkRow(title: String, subtitle: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
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
        .buttonStyle(.plain)
    }

    private func faqRow(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.tbBodyStrong)
                .foregroundStyle(TBTheme.deepSky)

            Text(answer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
        )
    }
}

struct PayoutSettingsView: View {
    @AppStorage("sellerEmail") private var sellerEmail = ""
    @State private var draft = SellerPayoutSettingsDraft.load()
    @State private var saveMessage: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TBTheme.spacingLG) {
                SellerSettingsHeader(
                    title: "Payout Settings",
                    subtitle: "Set a clean preview of how seller payouts, banking details, and notifications will look."
                )

                SellerSettingsCard(title: "Payout Schedule") {
                    Picker("Schedule", selection: $draft.schedule) {
                        ForEach(SellerPayoutSchedule.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    SellerSettingsToggleField(
                        title: "Email payout updates",
                        subtitle: "Get notified when transfers are scheduled or delayed.",
                        isOn: $draft.emailNotificationsEnabled
                    )
                }

                SellerSettingsCard(title: "Banking") {
                    SellerSettingsTextField(
                        title: "Account holder",
                        text: $draft.accountHolder,
                        prompt: "PrintCraft Studio LLC"
                    )

                    SellerSettingsTextField(
                        title: "Bank name",
                        text: $draft.bankName,
                        prompt: "Chase"
                    )

                    SellerSettingsTextField(
                        title: "Account ending",
                        text: $draft.accountLast4,
                        prompt: "4242"
                    )
                    .keyboardType(.numberPad)

                    SellerSettingsTextField(
                        title: "Payout email",
                        text: Binding(
                            get: { draft.payoutEmail.isEmpty ? sellerEmail : draft.payoutEmail },
                            set: { draft.payoutEmail = $0 }
                        ),
                        prompt: "seller@email.com"
                    )
                    .keyboardType(.emailAddress)
                }

                SellerSettingsCard(title: "Preview Note") {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TBTheme.icyBlue)

                        Text("This is a local preview of payout details. Real bank onboarding and transfer verification can hook into Stripe later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
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
        .background(TBTheme.cloudWhite.ignoresSafeArea())
        .navigationTitle("Payout")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            SellerSettingsSaveBar(title: "Save Payout Settings", action: savePayoutSettings)
        }
    }

    private func savePayoutSettings() {
        draft.accountLast4 = String(draft.accountLast4.filter(\.isNumber).prefix(4))
        draft.payoutEmail = draft.payoutEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.store()
        saveMessage = "Payout settings saved locally."
    }
}

struct EditSellerProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalog: CatalogStore
    @AppStorage("catalogRefreshToken") private var catalogRefreshToken = 0
    @AppStorage("sellerBusinessName") private var storedBusinessName = ""
    @Binding var seller: SellerProfile

    @State private var draft: SellerProfileDraft
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(seller: Binding<SellerProfile>) {
        _seller = seller
        _draft = State(initialValue: SellerProfileDraft(seller: seller.wrappedValue))
    }

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
        .background(TBTheme.cloudWhite.ignoresSafeArea())
        .navigationTitle("Edit Profile")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
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
                .disabled(isSaving)
                .opacity(isSaving ? 0.75 : 1)
            }
            .padding(.horizontal, TBTheme.spacingLG)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
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
            }
        }
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

        let minDays = min(draft.shipsInMinDays, draft.shipsInMaxDays)
        let maxDays = max(draft.shipsInMinDays, draft.shipsInMaxDays)
        let materials = draft.materialList.isEmpty ? seller.materials : draft.materialList
        let processingTime = draft.processingTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? seller.processingTime
            : draft.processingTime.trimmingCharacters(in: .whitespacesAndNewlines)

        let request = UpdateSellerProfileRequest(
            displayName: trimmedDisplayName,
            handle: "@\(normalizedHandle)",
            bio: trimmedBio,
            websiteURL: draft.normalizedWebsiteURL?.absoluteString,
            location: trimmedLocation,
            materials: materials,
            processingTime: processingTime,
            shipsInMinDays: minDays,
            shipsInMaxDays: maxDays
        )

        isSaving = true
        defer { isSaving = false }

        do {
            let updatedSeller = try await SellerAPI.updateProfile(
                sellerId: seller.id,
                profile: request
            )
            seller = updatedSeller
            storedBusinessName = updatedSeller.displayName
            updatedSeller.storeLocally()
            catalog.upsertSellerProfile(updatedSeller)
            catalogRefreshToken += 1
            errorMessage = nil
            dismiss()
        } catch {
            let fallbackSeller = SellerProfile(
                id: seller.id,
                displayName: trimmedDisplayName,
                handle: "@\(normalizedHandle)",
                bio: trimmedBio,
                avatarURL: seller.avatarURL,
                bannerURL: seller.bannerURL,
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
                joinedAt: seller.joinedAt
            )
            seller = fallbackSeller
            storedBusinessName = fallbackSeller.displayName
            fallbackSeller.storeLocally()
            catalog.upsertSellerProfile(fallbackSeller)
            errorMessage = "Saved on this device. Server sync failed, so other devices will not see it yet."
        }
    }
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
    static let payout = "sellerPayoutSettingsData"
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

private enum SellerPayoutSchedule: String, CaseIterable, Codable, Identifiable {
    case weekly
    case biweekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .biweekly:
            return "Biweekly"
        case .monthly:
            return "Monthly"
        }
    }
}

private struct SellerPayoutSettingsDraft: Codable {
    var schedule: SellerPayoutSchedule
    var emailNotificationsEnabled: Bool
    var accountHolder: String
    var bankName: String
    var accountLast4: String
    var payoutEmail: String

    static func load() -> SellerPayoutSettingsDraft {
        if let data = UserDefaults.standard.data(forKey: SellerSettingsStorageKey.payout),
           let saved = try? JSONDecoder().decode(SellerPayoutSettingsDraft.self, from: data) {
            return saved
        }

        return SellerPayoutSettingsDraft(
            schedule: .weekly,
            emailNotificationsEnabled: true,
            accountHolder: "PrintCraft Studio",
            bankName: "Chase",
            accountLast4: "4242",
            payoutEmail: ""
        )
    }

    func store() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: SellerSettingsStorageKey.payout)
    }
}

private enum SellerProductDraftStorage {
    static func key(for sellerId: String) -> String {
        "sellerProductDraftsData.\(sellerId)"
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
                    productionPreviewURLString: product.productionPreviewURL?.absoluteString ?? ""
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
            shipsInDays: draft.shipsInMinDays...draft.shipsInMaxDays
        )
    }
}
