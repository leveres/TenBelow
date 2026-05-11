import Foundation
import Combine

@MainActor
final class ExchangeStore: ObservableObject {
    @Published private(set) var requestsByID: [String: ExchangeRequest]
    @Published private(set) var draftsByKey: [String: ExchangeRequestDraft]

    private let requestsStorageKey = "exchangeStore.requests"
    private let draftsStorageKey = "exchangeStore.drafts"
    private let eventStore: CommerceEventStore
    private let orderStore: OrderStore

    init(eventStore: CommerceEventStore, orderStore: OrderStore) {
        self.eventStore = eventStore
        self.orderStore = orderStore
        requestsByID = Dictionary(
            uniqueKeysWithValues: LocalCodableStore.load(
                key: requestsStorageKey,
                default: [ExchangeRequest]()
            ).map { ($0.id, $0) }
        )
        draftsByKey = LocalCodableStore.load(key: draftsStorageKey, default: [:])
    }

    func request(withId id: String) -> ExchangeRequest? {
        requestsByID[id]
    }

    func requests(for orderId: String) -> [ExchangeRequest] {
        requestsByID.values
            .filter { $0.orderId == orderId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func draft(orderId: String, orderItemId: String) -> ExchangeRequestDraft? {
        draftsByKey[draftKey(orderId: orderId, orderItemId: orderItemId)]
    }

    func saveDraft(_ draft: ExchangeRequestDraft) {
        draftsByKey[draftKey(orderId: draft.orderId, orderItemId: draft.orderItemId)] = draft
        persistDrafts()
    }

    func clearDraft(orderId: String, orderItemId: String) {
        draftsByKey.removeValue(forKey: draftKey(orderId: orderId, orderItemId: orderItemId))
        persistDrafts()
    }

    func refreshRequests(for orderId: String) async throws -> [ExchangeRequest] {
        let fetched = try await ExchangeAPI.fetchRequests(orderId: orderId)
        upsert(fetched)
        orderStore.applyExchangeRequests(fetched, to: orderId)
        return fetched
    }

    func fetchRequest(id: String) async throws -> ExchangeRequest {
        let fetched = try await ExchangeAPI.fetchRequest(id: id)
        upsert(fetched)
        orderStore.applyExchangeRequests(requests(for: fetched.orderId), to: fetched.orderId)
        return fetched
    }

    func cancelRequest(id: String) async throws -> ExchangeRequest {
        let cancelled = try await ExchangeAPI.cancelRequest(id: id)
        upsert(cancelled)
        orderStore.applyExchangeRequests(requests(for: cancelled.orderId), to: cancelled.orderId)
        recordExchangeEvent(
            kind: .exchangeStatusUpdated,
            request: cancelled,
            metadata: ["status": cancelled.status.rawValue]
        )
        return cancelled
    }

    func submitDraft(
        orderId: String,
        orderItemId: String,
        reasonCode: ExchangeReasonCode,
        buyerExplanation: String,
        assets: [ExchangeLocalDraftAsset],
        originalVariantSnapshot: [String: String] = [:],
        progress: @escaping (Double) -> Void
    ) async throws -> ExchangeRequest {
        let created = try await ExchangeAPI.createRequest(
            orderId: orderId,
            orderItemId: orderItemId,
            reasonCode: reasonCode,
            buyerExplanation: buyerExplanation,
            originalVariantSnapshot: originalVariantSnapshot
        )
        upsert(created)
        progress(0)

        var latestRequest = created
        let totalAssetCount = max(assets.count, 1)
        for (index, asset) in assets.enumerated() {
            let uploadResult = try await ExchangeAPI.uploadProof(
                exchangeRequestId: created.id,
                asset: asset
            )
            latestRequest = uploadResult.exchangeRequest
            upsert(latestRequest)
            recordExchangeEvent(
                kind: .exchangeProofUploaded,
                request: latestRequest,
                metadata: [
                    "assetId": uploadResult.asset.id,
                    "assetType": uploadResult.asset.type.rawValue
                ]
            )
            progress(Double(index + 1) / Double(totalAssetCount))
        }

        let finalRequest = try await fetchRequest(id: latestRequest.id)
        clearDraft(orderId: orderId, orderItemId: orderItemId)
        orderStore.applyExchangeRequests(requests(for: orderId), to: orderId)
        recordExchangeEvent(
            kind: .exchangeSubmitted,
            request: finalRequest,
            metadata: [
                "status": finalRequest.status.rawValue,
                "reasonCode": finalRequest.reasonCode.rawValue
            ]
        )
        progress(1)
        return finalRequest
    }

    private func upsert(_ request: ExchangeRequest) {
        requestsByID[request.id] = request
        persistRequests()
    }

    private func upsert(_ requests: [ExchangeRequest]) {
        for request in requests {
            requestsByID[request.id] = request
        }
        persistRequests()
    }

    private func persistRequests() {
        let requests = requestsByID.values.sorted { $0.updatedAt > $1.updatedAt }
        LocalCodableStore.save(requests, key: requestsStorageKey)
    }

    private func persistDrafts() {
        LocalCodableStore.save(draftsByKey, key: draftsStorageKey)
    }

    private func draftKey(orderId: String, orderItemId: String) -> String {
        "\(orderId)|\(orderItemId)"
    }

    private func recordExchangeEvent(
        kind: CommerceEventKind,
        request: ExchangeRequest,
        metadata: [String: String]
    ) {
        eventStore.record(
            CommerceEvent(
                kind: kind,
                buyerIdentity: request.buyerUserId,
                productId: request.productId,
                orderId: request.orderId,
                sellerId: request.sellerUserId.replacingOccurrences(of: "seller:", with: ""),
                metadata: [
                    "exchangeRequestId": request.id,
                    "status": request.status.rawValue
                ].merging(metadata) { _, new in new }
            )
        )
    }
}
