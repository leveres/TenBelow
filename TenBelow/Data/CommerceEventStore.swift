import Foundation
import Combine

@MainActor
final class CommerceEventStore: ObservableObject {
    @Published private(set) var recentEvents: [CommerceEvent]

    private let storageKey = "commerceEventStore.recentEvents"
    private let maximumStoredEvents = 200

    init() {
        recentEvents = LocalCodableStore.load(
            key: storageKey,
            default: []
        )
    }

    func record(_ event: CommerceEvent) {
        recentEvents.insert(event, at: 0)
        if recentEvents.count > maximumStoredEvents {
            recentEvents = Array(recentEvents.prefix(maximumStoredEvents))
        }
        persist()
    }

    private func persist() {
        LocalCodableStore.save(recentEvents, key: storageKey)
    }

    /// Counts marketplace-wide favorite events for a product within a recent window (all buyers on this device).
    func recentProductFavoriteCount(
        productId: String,
        within interval: TimeInterval = 7 * 24 * 60 * 60
    ) -> Int {
        let trimmedProductId = productId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProductId.isEmpty else { return 0 }

        let cutoff = Date().addingTimeInterval(-interval)
        return recentEvents.filter { event in
            event.kind == .productFavorited
                && event.productId == trimmedProductId
                && event.createdAt >= cutoff
        }.count
    }
}
