import SwiftUI
import PhotosUI
import AVFoundation
import Combine
#if os(iOS)
import UIKit
#endif

struct ExchangeOrderItemContext: Identifiable, Hashable {
    let orderId: String
    let shipmentId: String
    let sellerId: String
    let sellerName: String
    let item: OrderLineItem

    var id: String { item.id }
    var productTitle: String { item.productName }
    var imageURL: URL? {
        guard let thumbnailURL = item.thumbnailURL else { return nil }
        return URL(string: thumbnailURL)
    }
}

@MainActor
final class ExchangeEligibilityViewModel: ObservableObject {
    @Published private(set) var eligibilityByItemID: [String: ExchangeEligibilityResult] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func loadEligibility(for items: [ExchangeOrderItemContext]) async {
        guard !items.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        for item in items {
            do {
                let result = try await ExchangeAPI.checkEligibility(
                    orderId: item.orderId,
                    orderItemId: item.item.id
                )
                eligibilityByItemID[item.item.id] = result
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func eligibility(for itemId: String) -> ExchangeEligibilityResult? {
        eligibilityByItemID[itemId]
    }
}

@MainActor
final class ExchangeRequestViewModel: ObservableObject {
    @Published var selectedItemId: String
    @Published var selectedReasonCode: ExchangeReasonCode?
    @Published var buyerExplanation: String
    @Published var draftAssets: [ExchangeLocalDraftAsset]
    @Published private(set) var eligibilityResult: ExchangeEligibilityResult?
    @Published private(set) var isCheckingEligibility = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var submitProgress: Double = 0
    @Published private(set) var submittedRequest: ExchangeRequest?
    @Published var errorMessage: String?
    @Published var proofMessage: String?

    let order: Order
    let config: AppConfig

    private let exchangeStore: ExchangeStore
    private let availableItems: [ExchangeOrderItemContext]

    init(
        order: Order,
        availableItems: [ExchangeOrderItemContext],
        exchangeStore: ExchangeStore,
        config: AppConfig
    ) {
        self.order = order
        self.availableItems = availableItems
        self.exchangeStore = exchangeStore
        self.config = config

        let initialItemId = availableItems.first?.item.id ?? ""
        if let existingDraft = availableItems.first.flatMap({ exchangeStore.draft(orderId: order.id, orderItemId: $0.item.id) }) {
            selectedItemId = existingDraft.orderItemId
            selectedReasonCode = existingDraft.reasonCode
            buyerExplanation = existingDraft.buyerExplanation
            draftAssets = existingDraft.localAssets
        } else {
            selectedItemId = initialItemId
            selectedReasonCode = nil
            buyerExplanation = ""
            draftAssets = []
        }
    }

    var selectableItems: [ExchangeOrderItemContext] {
        availableItems
    }

    var selectedItem: ExchangeOrderItemContext? {
        availableItems.first(where: { $0.item.id == selectedItemId })
    }

    var explanationCharacterCount: Int {
        buyerExplanation.count
    }

    var canContinueFromReason: Bool {
        selectedReasonCode != nil && !trimmedExplanation.isEmpty
    }

    var canContinueFromProof: Bool {
        imageAssets.count >= config.minProofImages && imageAssets.count <= config.maxProofImages
    }

    var canSubmit: Bool {
        canContinueFromReason && canContinueFromProof && selectedItem != nil && !isSubmitting
    }

    var imageAssets: [ExchangeLocalDraftAsset] {
        draftAssets.filter { $0.type == .image }
    }

    var videoAsset: ExchangeLocalDraftAsset? {
        draftAssets.first(where: { $0.type == .video })
    }

    func selectItem(_ itemId: String) {
        guard itemId != selectedItemId else { return }
        selectedItemId = itemId
        if let existingDraft = exchangeStore.draft(orderId: order.id, orderItemId: itemId) {
            selectedReasonCode = existingDraft.reasonCode
            buyerExplanation = existingDraft.buyerExplanation
            draftAssets = existingDraft.localAssets
        } else {
            selectedReasonCode = nil
            buyerExplanation = ""
            draftAssets = []
        }
        persistDraft()
    }

    func refreshEligibility() async {
        guard let selectedItem else { return }
        isCheckingEligibility = true
        errorMessage = nil
        defer { isCheckingEligibility = false }

        do {
            eligibilityResult = try await ExchangeAPI.checkEligibility(
                orderId: selectedItem.orderId,
                orderItemId: selectedItem.item.id
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSelectedImages(from items: [PhotosPickerItem]) async {
        var nextAssets = draftAssets.filter { $0.type != .image }
        var loadedAssets: [ExchangeLocalDraftAsset] = []

        for item in items.prefix(config.maxProofImages) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                #if os(iOS)
                guard let image = UIImage(data: data) else { continue }
                guard let compressedData = ExchangeProofDraftLoader.compressedJPEGData(from: image) else { continue }
                let fileURL = try ExchangeProofDraftLoader.writeTemporaryAsset(
                    data: compressedData,
                    fileExtension: "jpg"
                )
                loadedAssets.append(
                    ExchangeLocalDraftAsset(
                        type: .image,
                        localFileURLString: fileURL.path,
                        thumbnailURLString: fileURL.path
                    )
                )
                #endif
            } catch {
                proofMessage = "We couldn't load one of the selected images."
            }
        }

        nextAssets.append(contentsOf: loadedAssets)
        draftAssets = nextAssets
        proofMessage = loadedAssets.count < config.minProofImages
            ? "Please upload at least \(config.minProofImages) clear photo\(config.minProofImages == 1 ? "" : "s")."
            : nil
        persistDraft()
    }

    func loadSelectedVideo(from item: PhotosPickerItem?) async {
        draftAssets.removeAll(where: { $0.type == .video })
        guard let item else {
            persistDraft()
            return
        }

        do {
            guard config.allowProofVideo else { return }
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
            let fileURL = try ExchangeProofDraftLoader.writeTemporaryAsset(
                data: data,
                fileExtension: fileExtension
            )
            let durationSeconds = try await ExchangeProofDraftLoader.videoDurationSeconds(for: fileURL)
            guard durationSeconds <= Double(config.maxVideoDurationSeconds) else {
                proofMessage = "Keep proof videos under \(config.maxVideoDurationSeconds) seconds."
                persistDraft()
                return
            }

            draftAssets.append(
                ExchangeLocalDraftAsset(
                    type: .video,
                    localFileURLString: fileURL.path,
                    thumbnailURLString: nil
                )
            )
            proofMessage = nil
            persistDraft()
        } catch {
            proofMessage = "We couldn't load that video clip."
        }
    }

    func removeAsset(_ asset: ExchangeLocalDraftAsset) {
        if let url = asset.localFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let thumbnailURL = asset.thumbnailURL {
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
        draftAssets.removeAll { $0.id == asset.id }
        persistDraft()
    }

    func persistDraft() {
        guard let selectedItem else { return }
        let draft = ExchangeRequestDraft(
            orderId: order.id,
            orderItemId: selectedItem.item.id,
            reasonCode: selectedReasonCode,
            buyerExplanation: buyerExplanation,
            localAssets: draftAssets,
            updatedAt: .now
        )
        exchangeStore.saveDraft(draft)
    }

    func submit() async {
        guard let selectedItem, let selectedReasonCode else { return }

        isSubmitting = true
        submitProgress = 0
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let request = try await exchangeStore.submitDraft(
                orderId: order.id,
                orderItemId: selectedItem.item.id,
                reasonCode: selectedReasonCode,
                buyerExplanation: trimmedExplanation,
                assets: draftAssets,
                progress: { [weak self] value in
                    Task { @MainActor in
                        self?.submitProgress = value
                    }
                }
            )
            submittedRequest = request
            eligibilityResult = ExchangeEligibilityResult(
                isEligible: request.eligibleAtSubmission,
                failureCode: nil,
                failureMessage: request.eligibilityFailureReason,
                exchangeEligibleUntil: selectedItem.item.exchangeEligibleUntil,
                exchangeCount: selectedItem.item.exchangeCount ?? 0,
                needsAdminReview: config.requireAdminForApproval,
                allowedResolutionTypes: [.sameItemExchange]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var trimmedExplanation: String {
        buyerExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class ExchangeStatusViewModel: ObservableObject {
    @Published private(set) var exchangeRequest: ExchangeRequest?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let exchangeRequestId: String
    private let exchangeStore: ExchangeStore

    init(exchangeRequestId: String, exchangeStore: ExchangeStore) {
        self.exchangeRequestId = exchangeRequestId
        self.exchangeStore = exchangeStore
        self.exchangeRequest = exchangeStore.request(withId: exchangeRequestId)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            exchangeRequest = try await exchangeStore.fetchRequest(id: exchangeRequestId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelIfAllowed() async {
        guard let exchangeRequest, ["awaiting_buyer_proof", "submitted"].contains(exchangeRequest.status.rawValue) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            self.exchangeRequest = try await exchangeStore.cancelRequest(id: exchangeRequest.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum ExchangeProofDraftLoader {
    #if os(iOS)
    static func compressedJPEGData(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1800
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let targetSize: CGSize
        if max(image.size.width, image.size.height) > maxDimension {
            let scale = maxDimension / max(image.size.width, image.size.height)
            targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        } else {
            targetSize = image.size
        }

        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: 0.84)
    }
    #endif

    static func writeTemporaryAsset(data: Data, fileExtension: String) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    static func videoDurationSeconds(for fileURL: URL) async throws -> Double {
        let asset = AVURLAsset(url: fileURL)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }
}
