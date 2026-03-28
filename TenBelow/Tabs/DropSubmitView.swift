//
//  DropSubmitView.swift
//  TenBelow
//

import SwiftUI
import PhotosUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers

struct DropSubmitView: View {
    @AppStorage("sellerSellerId") private var sellerId = ""
    @AppStorage("sellerPreviewMode") private var sellerPreviewMode = false
    @AppStorage("catalogRefreshToken") private var catalogRefreshToken = 0
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sellerSubscription: SellerSubscriptionStore

    @State private var submissions: SellerSubmissionsResponse?
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showSubscriptionCenter = false
    @State private var editingProduct: DropProduct?
    @State private var draftProductId = "drop-\(UUID().uuidString)"
    @State private var selectedImageItems: [PhotosPickerItem] = []
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedImageURLStrings: [String] = []
    @State private var selectedVideoURL: URL?
    @State private var selectedVideoPlayer: AVPlayer?
    @State private var selectedVideoDurationSeconds: Double?
    @State private var mediaErrorMessage: String?
    @State private var draggedImageURLString: String?

    // Form fields
    @State private var productName = ""
    @State private var priceString = ""
    @State private var selectedCategory: Category = .home
    @State private var material = ""
    @State private var durabilityNote = ""
    @State private var careWarning = ""
    @State private var shipsMinDays = 3
    @State private var shipsMaxDays = 7

    private var priceCents: Int {
        let dollars = Double(priceString) ?? 0
        return Int(dollars * 100)
    }

    private var priceValid: Bool { priceCents >= DropConstants.minPriceCents }
    private var slotsUsed: Int { submissions?.slotsUsed ?? 0 }
    private var slotsMax: Int { submissions?.slotsMax ?? DropConstants.maxSlotsPerSeller }
    private var slotsRemaining: Int { slotsMax - slotsUsed }
    private var isWindowOpen: Bool { submissions?.isActive ?? false }
    private var isShowingLoadingOverlay: Bool { isLoading || isSubmitting }
    private let maxVideoDurationSeconds: Double = 45
    private var hasDropAccess: Bool { sellerPreviewMode || sellerSubscription.hasActiveSubscription }
    private var videoDurationValid: Bool {
        guard let selectedVideoDurationSeconds else { return true }
        return selectedVideoDurationSeconds <= maxVideoDurationSeconds
    }

    private var canSubmit: Bool {
        !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && priceValid
            && slotsRemaining > 0
            && isWindowOpen
            && hasDropAccess
            && videoDurationValid
            && !isSubmitting
    }

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: TBTheme.spacingXL) {

                    windowStatusBanner
                    subscriptionBanner

                    slotCounter

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if let msg = successMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(msg)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }

                    if hasDropAccess && isWindowOpen && slotsRemaining > 0 {
                        submissionForm
                    }

                    mySubmissionsList
                }
                .padding()
            }
            .background(TBTheme.cloudWhite)

            if isShowingLoadingOverlay {
                AppLoadingOverlay(
                    title: isSubmitting ? "Submitting product" : "Loading drop window",
                    subtitle: isSubmitting
                        ? "Sending your listing for review."
                        : "Checking your slots and submission window."
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .navigationTitle("Weekly Drop")
        .sheet(isPresented: $showSubscriptionCenter) {
            SellerSubscriptionView()
        }
        .task {
            await sellerSubscription.refresh()
            await loadSubmissions()
        }
        .onChange(of: selectedImageItems) { _, newItems in
            Task { await loadSelectedImages(from: newItems) }
        }
        .onChange(of: selectedVideoItem) { _, newItem in
            Task { await loadSelectedVideo(from: newItem) }
        }
        .onChange(of: selectedVideoURL) { _, newURL in
            updateSelectedVideoPlayer(with: newURL)
        }
    }

    // MARK: - Window status

    @ViewBuilder
    private var windowStatusBanner: some View {
        if let subs = submissions {
            HStack(spacing: 10) {
                Image(systemName: subs.isActive ? "flame.fill" : "clock")
                    .font(.title3)
                    .foregroundStyle(subs.isActive ? .orange : TBTheme.skyBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(subs.isActive ? "Drop Window Open" : "Drop Window Closed")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(subs.isActive ? .orange : .secondary)

                    if subs.isActive {
                        Text("Submit eligible products before Sunday midnight UTC.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let next = subs.nextDropAt {
                        Text("Next drop opens \(DropCountdown.timeLeft(until: next))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(TBTheme.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .fill(subs.isActive ? Color.orange.opacity(0.08) : TBTheme.subtleGray)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .strokeBorder(subs.isActive ? Color.orange.opacity(0.2) : TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var subscriptionBanner: some View {
        if !hasDropAccess {
            VStack(alignment: .leading, spacing: 10) {
                Label("Seller membership required", systemImage: "creditcard")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)

                Text("Activate your App Store membership to submit to Weekly Drop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showSubscriptionCenter = true
                } label: {
                    Text("Start at \(sellerSubscription.displayPrice) / month")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(TBTheme.spacingMD)
            .background(TBTheme.cardGradient)
            .cornerRadius(TBTheme.radiusLG)
            .overlay(
                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - Slot counter

    @ViewBuilder
    private var slotCounter: some View {
        HStack {
            Text("Slots Used")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                ForEach(0..<slotsMax, id: \.self) { i in
                    Circle()
                        .fill(i < slotsUsed ? TBTheme.accent : TBTheme.skyBlue.opacity(0.2))
                        .frame(width: 12, height: 12)
                }
            }
            Text("\(slotsUsed)/\(slotsMax)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TBTheme.deepSky)
        }
        .padding(TBTheme.spacingMD)
        .background(TBTheme.cardGradient)
        .cornerRadius(TBTheme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .strokeBorder(TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Submission form

    @ViewBuilder
    private var submissionForm: some View {
        GlassCard(cornerRadius: 22, showsBorder: false) {
            VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                Text(editingProduct == nil ? "Add drop product" : "Edit drop product")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.frostTitleGradient)

                mediaSection

                dropGlassField("Product name", text: $productName)

                HStack(spacing: 10) {
                    Text("$")
                        .font(.headline)
                        .foregroundStyle(TBTheme.icyBlue)
                        .padding(.leading, 14)
                    TextField("Price (example: 15.00)", text: $priceString)
                        .textFieldStyle(.plain)
                        .font(.tbBody)
                        .keyboardType(.decimalPad)
                        .padding(.trailing, 14)
                }
                .padding(.vertical, 13)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
                )

                if !priceString.isEmpty && !priceValid {
                    Text("Price must be above $10.00 for Weekly Drop.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if editingProduct != nil {
                    Button {
                        clearForm()
                    } label: {
                        Text("Cancel edit")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TBTheme.deepSky)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Picker("Category", selection: $selectedCategory) {
                    ForEach(Category.allCases) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
                )

                dropGlassField("Material (e.g. PETG, Resin)", text: $material)
                dropGlassField("Durability note", text: $durabilityNote)
                dropGlassField("Care warning (optional)", text: $careWarning)

                HStack {
                    Stepper("Ships in \(shipsMinDays)–\(shipsMaxDays) days", value: $shipsMinDays, in: 1...14)
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
                )

                Button {
                    Task { await submitProduct() }
                } label: {
                    if isSubmitting {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding()
                    } else {
                        Text(editingProduct == nil ? "Submit to Drop" : "Save Changes")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
            }
        }
    }

    @ViewBuilder
    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Media")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let mediaErrorMessage {
                Text(mediaErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Add up to 5 photos and 1 video (max \(Int(maxVideoDurationSeconds))s).")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $selectedImageItems,
                    maxSelectionCount: 5,
                    matching: .images
                ) {
                    dropMediaPickerButtonLabel(
                        title: "Add Photos",
                        icon: "photo.on.rectangle.angled"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add photos")
                .accessibilityHint("Choose up to 5 product photos.")

                PhotosPicker(
                    selection: $selectedVideoItem,
                    matching: .videos
                ) {
                    dropMediaPickerButtonLabel(
                        title: selectedVideoURL == nil ? "Add Video" : "Replace Video",
                        icon: "video.badge.plus"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selectedVideoURL == nil ? "Add video" : "Replace video")
                .accessibilityHint("Choose one product video.")
            }

            if !selectedImageURLStrings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(selectedImageURLStrings, id: \.self) { imageURLString in
                            imageThumbnail(for: imageURLString)
                        }
                    }
                }
            }

            if selectedVideoURL != nil {
                ZStack(alignment: .topTrailing) {
                    VideoPlayer(player: selectedVideoPlayer)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(TBTheme.skyBlue.opacity(0.2), lineWidth: 1)
                        )

                    Button {
                        removeSelectedVideo()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .black.opacity(0.75))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove video")
                }

                if let selectedVideoDurationSeconds {
                    Text("Video length: \(Int(selectedVideoDurationSeconds))s")
                        .font(.caption)
                        .foregroundColor(videoDurationValid ? .secondary : .red)
                }
            }

            if !videoDurationValid {
                Text("Video must be \(Int(maxVideoDurationSeconds)) seconds or shorter.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - My submissions list

    @ViewBuilder
    private var mySubmissionsList: some View {
        if let subs = submissions, !subs.products.isEmpty {
            VStack(alignment: .leading, spacing: TBTheme.spacingMD) {
                Text("Your submissions this week")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.icyBlue)

                ForEach(subs.products) { product in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.name)
                                .font(.tbProductTitleSM)
                                .tbProductNameTitleStyle()
                            Text(Money.format(cents: product.priceCents))
                                .font(.tbProductPriceSM)
                                .foregroundStyle(.primary.opacity(0.82))
                            Text(product.material)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 10) {
                            if isWindowOpen {
                                Button {
                                    beginEditing(product)
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(TBTheme.deepSky)
                                        .padding(8)
                                        .background(TBTheme.skyBlue.opacity(0.12), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Edit \(product.name)")

                                Button(role: .destructive) {
                                    Task { await deleteProduct(product.id) }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.subheadline)
                                }
                                .accessibilityLabel("Delete \(product.name)")
                            }
                        }
                    }
                    .padding(TBTheme.spacingMD)
                    .background(TBTheme.cardGradient)
                    .cornerRadius(TBTheme.radiusLG)
                    .overlay(
                        RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(isWindowOpen ? .isButton : [])
                    .accessibilityLabel("\(product.name), \(Money.format(cents: product.priceCents)), \(product.material)")
                    .accessibilityHint(isWindowOpen ? "Double-tap to edit this submission." : "")
                    .accessibilityAction {
                        guard isWindowOpen else { return }
                        beginEditing(product)
                    }
                    .onTapGesture {
                        guard isWindowOpen else { return }
                        beginEditing(product)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadSubmissions() async {
        guard !sellerId.isEmpty else { return }
        if sellerPreviewMode {
            if submissions == nil {
                submissions = makeLocalSubmissions(products: [])
            }
            return
        }
        isLoading = true
        do {
            submissions = try await DropAPI.mySubmissions(sellerId: sellerId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func submitProduct() async {
        guard hasDropAccess else {
            showSubscriptionCenter = true
            return
        }
        guard isWindowOpen else {
            errorMessage = "Submissions are open Friday through Sunday."
            return
        }
        guard slotsRemaining > 0 else {
            errorMessage = "All slots are used for this week."
            return
        }
        guard priceValid else {
            errorMessage = "Weekly Drop requires prices above $10.00."
            return
        }
        guard !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a product name."
            return
        }

        errorMessage = nil
        successMessage = nil
        isSubmitting = true

        let trimmedName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        let warnings = careWarning.isEmpty ? [] : [careWarning]

        let productId = editingProduct?.id ?? draftProductId

        if sellerPreviewMode {
            let request = DropSubmissionRequest(
                productId: productId,
                sellerId: sellerId,
                name: trimmedName,
                priceCents: priceCents,
                category: selectedCategory.rawValue,
                imageURLs: selectedImageURLStrings,
                demoVideoURL: selectedVideoURL?.absoluteString,
                material: material.isEmpty ? "PLA+" : material,
                durabilityNote: durabilityNote,
                careWarnings: warnings,
                shipsInMinDays: shipsMinDays,
                shipsInMaxDays: shipsMaxDays
            )
            saveLocally(request: request)
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            clearForm()
            isSubmitting = false
            return
        }

        do {
            let media = try await persistSelectedMedia(productId: productId)
            let request = DropSubmissionRequest(
                productId: productId,
                sellerId: sellerId,
                name: trimmedName,
                priceCents: priceCents,
                category: selectedCategory.rawValue,
                imageURLs: media.imageURLs,
                demoVideoURL: media.demoVideoURL,
                material: material.isEmpty ? "PLA+" : material,
                durabilityNote: durabilityNote,
                careWarnings: warnings,
                shipsInMinDays: shipsMinDays,
                shipsInMaxDays: shipsMaxDays
            )
            let product: DropProduct
            if let editingProduct {
                product = try await DropAPI.updateSubmission(productId: editingProduct.id, request: request)
                successMessage = "\(product.name) updated."
            } else {
                product = try await DropAPI.submitProduct(request)
                successMessage = "\(product.name) submitted."
            }

            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif

            clearForm()
            catalogRefreshToken += 1

            await loadSubmissions()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    private func deleteProduct(_ productId: String) async {
        if sellerPreviewMode {
            let products = submissions?.products.filter { $0.id != productId } ?? []
            withAnimation(.easeInOut(duration: 0.2)) {
                submissions = makeLocalSubmissions(products: products)
            }
            if editingProduct?.id == productId {
                clearForm()
            }
            return
        }

        do {
            try await DropAPI.deleteSubmission(productId: productId)
            if editingProduct?.id == productId {
                clearForm()
            }
            catalogRefreshToken += 1
            await loadSubmissions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginEditing(_ product: DropProduct) {
        withAnimation(.easeInOut(duration: 0.2)) {
            editingProduct = product
        }
        draftProductId = product.id
        productName = product.name
        priceString = String(format: "%.2f", Double(product.priceCents) / 100)
        selectedCategory = Category(rawValue: product.category) ?? .home
        material = product.material
        durabilityNote = product.durabilityNote
        careWarning = product.careWarnings.first ?? ""
        shipsMinDays = product.shipsInMinDays
        shipsMaxDays = max(product.shipsInMaxDays, product.shipsInMinDays)
        selectedImageItems = []
        selectedVideoItem = nil
        selectedVideoURL = product.demoVideoURL.flatMap(urlFromString)
        selectedImageURLStrings = product.imageURLs
    }

    private func clearForm() {
        withAnimation(.easeInOut(duration: 0.2)) {
            editingProduct = nil
        }
        draftProductId = "drop-\(UUID().uuidString)"
        productName = ""
        priceString = ""
        material = ""
        durabilityNote = ""
        careWarning = ""
        shipsMinDays = 3
        shipsMaxDays = 7
        selectedCategory = .home
        selectedImageItems = []
        selectedVideoItem = nil
        selectedImageURLStrings = []
        selectedVideoURL = nil
        selectedVideoPlayer = nil
        selectedVideoDurationSeconds = nil
        mediaErrorMessage = nil
        draggedImageURLString = nil
    }

    private func saveLocally(request: DropSubmissionRequest) {
        var products = submissions?.products ?? []
        let product = DropProduct(
            id: request.productId,
            sellerId: request.sellerId,
            name: request.name,
            priceCents: request.priceCents,
            category: request.category,
            imageURLs: request.imageURLs,
            demoVideoURL: request.demoVideoURL,
            material: request.material,
            durabilityNote: request.durabilityNote,
            careWarnings: request.careWarnings,
            shipsInMinDays: request.shipsInMinDays,
            shipsInMaxDays: request.shipsInMaxDays,
            submittedAt: editingProduct?.submittedAt ?? ISO8601DateFormatter().string(from: Date())
        )

        if let editingProduct, let index = products.firstIndex(where: { $0.id == editingProduct.id }) {
            products[index] = product
            successMessage = "\(product.name) updated."
        } else {
            products.insert(product, at: 0)
            successMessage = "\(product.name) submitted."
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            submissions = makeLocalSubmissions(products: products)
        }
    }

    private func makeLocalSubmissions(products: [DropProduct]) -> SellerSubmissionsResponse {
        SellerSubmissionsResponse(
            sellerId: sellerId,
            weekId: "local-preview-week",
            isActive: true,
            nextDropAt: nil,
            slotsUsed: products.count,
            slotsMax: DropConstants.maxSlotsPerSeller,
            products: products
        )
    }

    private func loadSelectedImages(from items: [PhotosPickerItem]) async {
        var loadedURLs: [String] = []
        for item in items.prefix(5) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpgData = image.jpegData(compressionQuality: 0.88),
                  let imageURL = writeTempFile(data: jpgData, fileExtension: "jpg")
            else {
                await MainActor.run {
                    mediaErrorMessage = "We couldn't load one of the selected images."
                }
                continue
            }
            loadedURLs.append(imageURL.absoluteString)
        }

        await MainActor.run {
            selectedImageURLStrings = loadedURLs
            if !loadedURLs.isEmpty {
                mediaErrorMessage = nil
            }
            draggedImageURLString = nil
        }
    }

    private func loadSelectedVideo(from item: PhotosPickerItem?) async {
        guard let item else {
            await MainActor.run { selectedVideoURL = nil }
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let videoURL = writeTempFile(data: data, fileExtension: "mov")
            else {
                await MainActor.run {
                    mediaErrorMessage = "We couldn't load that video clip."
                }
                return
            }

            await MainActor.run {
                selectedVideoURL = videoURL
            }

            let durationSeconds = try await videoDurationSeconds(for: videoURL)

            await MainActor.run {
                selectedVideoDurationSeconds = durationSeconds
                mediaErrorMessage = durationSeconds > maxVideoDurationSeconds
                    ? "Video is too long. Keep clips under \(Int(maxVideoDurationSeconds)) seconds."
                    : nil
            }
        } catch {
            await MainActor.run {
                mediaErrorMessage = "We couldn't load that video clip."
            }
        }
    }

    private func imageThumbnail(for imageURLString: String) -> some View {
        ZStack(alignment: .topTrailing) {
            if let url = URL(string: imageURLString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(TBTheme.skyBlue.opacity(0.12))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(TBTheme.skyBlue.opacity(0.2), lineWidth: 1)
                )
                .onDrag {
                    draggedImageURLString = imageURLString
                    return NSItemProvider(object: imageURLString as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: DropMediaImageReorderDelegate(
                        item: imageURLString,
                        items: $selectedImageURLStrings,
                        draggedItem: $draggedImageURLString
                    )
                )
                .accessibilityLabel("Selected product image")
            }

            Button {
                removeSelectedImage(imageURLString)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white, .black.opacity(0.75))
                    .padding(4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove image")
        }
    }

    private func removeSelectedImage(_ imageURLString: String) {
        selectedImageURLStrings.removeAll { $0 == imageURLString }
        selectedImageItems = []
    }

    private func removeSelectedVideo() {
        selectedVideoItem = nil
        selectedVideoURL = nil
        selectedVideoPlayer = nil
        selectedVideoDurationSeconds = nil
        mediaErrorMessage = nil
    }

    private func persistSelectedMedia(productId: String) async throws -> (imageURLs: [String], demoVideoURL: String?) {
        let imageURLs = try await uploadSelectedImages(productId: productId)
        let demoVideoURL = try await uploadSelectedVideo(productId: productId)
        return (imageURLs, demoVideoURL)
    }

    private func uploadSelectedImages(productId: String) async throws -> [String] {
        var uploadedURLs: [String] = []

        for (index, reference) in selectedImageURLStrings.enumerated() {
            if Product.mediaURL(for: reference) != nil {
                uploadedURLs.append(reference)
                continue
            }

            guard let fileURL = urlFromString(reference), fileURL.isFileURL else {
                throw NSError(
                    domain: "DropSubmitView",
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

    private func uploadSelectedVideo(productId: String) async throws -> String? {
        guard let selectedVideoURL else { return nil }

        if let remoteURL = Product.mediaURL(for: selectedVideoURL.absoluteString) {
            return remoteURL.absoluteString
        }

        guard selectedVideoURL.isFileURL else {
            throw NSError(
                domain: "DropSubmitView",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The selected video could not be prepared."]
            )
        }

        let data = try Data(contentsOf: selectedVideoURL)
        let fileExtension = selectedVideoURL.pathExtension.lowercased().isEmpty ? "mov" : selectedVideoURL.pathExtension.lowercased()
        return try await SellerAPI.uploadMedia(
            sellerId: sellerId,
            productId: productId,
            mediaKind: "video",
            slot: "0",
            fileExtension: fileExtension,
            contentType: videoContentType(for: fileExtension),
            data: data
        )
    }

    private func imageContentType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        default:
            return "image/jpeg"
        }
    }

    private func videoContentType(for fileExtension: String) -> String {
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

    private func dropGlassField(_ title: String, text: Binding<String>) -> some View {
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

    private func dropMediaPickerButtonLabel(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(TBTheme.deepSky)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(TBTheme.skyBlue.opacity(0.14), lineWidth: 1)
            )
    }

    private func updateSelectedVideoPlayer(with url: URL?) {
        guard let url else {
            selectedVideoPlayer = nil
            return
        }
        if let player = selectedVideoPlayer {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        } else {
            selectedVideoPlayer = AVPlayer(url: url)
        }
    }

    private func writeTempFile(data: Data, fileExtension: String) -> URL? {
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

    private func urlFromString(_ value: String) -> URL? {
        URL(string: value)
    }

    private func isVideoURL(_ url: URL?) -> Bool {
        guard let pathExtension = url?.pathExtension.lowercased() else { return false }
        return ["mp4", "mov", "m4v", "avi", "hevc"].contains(pathExtension)
    }

    private func videoDurationSeconds(for videoURL: URL) async throws -> Double {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        guard CMTIME_IS_NUMERIC(duration) else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? max(0, seconds) : 0
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

#Preview {
    NavigationStack {
        DropSubmitView()
    }
    .environmentObject(SellerSubscriptionStore.previewActive)
}
