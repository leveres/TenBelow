import Foundation
import Combine

/// One conversation thread per buyer+seller pair (`buyerIdentity|sellerId`).
/// Persisted locally until a real backend exists.
///
/// **Product direction:** When the buyer taps Message on a storefront, push this thread (only messages
/// between the current buyer and that seller). A future **Inbox** tab can list `sellerIds` sorted by
/// `lastMessageDate` and navigate into the same `SellerMessagesView(seller:)`.
@MainActor
final class BuyerSellerThreadStore: ObservableObject {
    private static let storageKey = "BuyerSellerThreadStore.v1"

    @Published private(set) var messagesByThreadKey: [String: [BuyerSellerThreadMessage]] = [:]

    init() {
        load()
    }

    func messages(for sellerId: String) -> [BuyerSellerThreadMessage] {
        let key = threadKey(for: sellerId)
        return (messagesByThreadKey[key] ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    /// Seeds the first-open demo transcript once per seller (not overwritten after buyer sends).
    func bootstrapThreadIfNeeded(sellerId: String, sellerDisplayName: String) {
        let key = threadKey(for: sellerId)
        guard messagesByThreadKey[key] == nil else { return }
        messagesByThreadKey[key] = BuyerSellerThreadMessage.demoSeed(sellerDisplayName: sellerDisplayName)
        save()
    }

    func appendBuyerMessage(sellerId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = threadKey(for: sellerId)
        var list = messagesByThreadKey[key] ?? []
        list.append(
            BuyerSellerThreadMessage(
                id: UUID(),
                text: trimmed,
                isFromBuyer: true,
                createdAt: Date()
            )
        )
        messagesByThreadKey[key] = list
        save()
    }

    /// For a future inbox: sellers the buyer has a thread with, most recent first.
    func sellerIdsOrderedByRecentMessage() -> [String] {
        let prefix = currentBuyerIdentityKey + "|"
        let keysForCurrentBuyer = messagesByThreadKey.keys.filter { $0.hasPrefix(prefix) }
        return keysForCurrentBuyer.sorted { lhs, rhs in
            let l = messagesByThreadKey[lhs]?.map(\.createdAt).max() ?? .distantPast
            let r = messagesByThreadKey[rhs]?.map(\.createdAt).max() ?? .distantPast
            return l > r
        }
        .compactMap { key in
            key.components(separatedBy: "|").last
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([String: [BuyerSellerThreadMessage]].self, from: data)
            messagesByThreadKey = decoded
        } catch {
            messagesByThreadKey = [:]
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(messagesByThreadKey)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch { }
    }

    private var currentBuyerIdentityKey: String {
        let userDefaults = UserDefaults.standard
        let buyerAccountCreated = userDefaults.bool(forKey: "buyerAccountCreated")
        let email = userDefaults.string(forKey: "buyerEmail")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if buyerAccountCreated, !email.isEmpty {
            return "buyer:\(email)"
        }

        return "guest"
    }

    private func threadKey(for sellerId: String) -> String {
        "\(currentBuyerIdentityKey)|\(sellerId)"
    }
}

struct BuyerSellerThreadMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let isFromBuyer: Bool
    let createdAt: Date

    var timestampLabel: String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: createdAt)
    }

    static func demoSeed(sellerDisplayName: String) -> [BuyerSellerThreadMessage] {
        let cal = Calendar.current
        let base = Date()
        return [
            BuyerSellerThreadMessage(
                id: UUID(),
                text: "Hi, I’m interested in one of your products. Do you offer alternate filament colors?",
                isFromBuyer: true,
                createdAt: cal.date(byAdding: .hour, value: -2, to: base) ?? base
            ),
            BuyerSellerThreadMessage(
                id: UUID(),
                text: "Yes — tell me which listing you want and I’ll confirm what’s in stock.",
                isFromBuyer: false,
                createdAt: cal.date(byAdding: .minute, value: -110, to: base) ?? base
            ),
            BuyerSellerThreadMessage(
                id: UUID(),
                text: "Replies from \(sellerDisplayName) are usually within a few hours. This chat is only between you and this shop.",
                isFromBuyer: false,
                createdAt: cal.date(byAdding: .minute, value: -105, to: base) ?? base
            )
        ]
    }
}
