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
}
