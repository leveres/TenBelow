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
        migrateLegacyGuestThreadKeysIfNeeded()
    }

    func messages(for sellerId: String) -> [BuyerSellerThreadMessage] {
        let key = threadKey(for: sellerId)
        return (messagesByThreadKey[key] ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    func messages(for sellerId: String, buyerIdentity: String) -> [BuyerSellerThreadMessage] {
        let key = threadKey(for: sellerId, buyerIdentity: buyerIdentity)
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
                createdAt: Date(),
                buyerSenderName: Self.trimmedBuyerFullNameFromStorage()
            )
        )
        messagesByThreadKey[key] = list
        save()
    }

    func appendSellerMessage(sellerId: String, buyerIdentity: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = threadKey(for: sellerId, buyerIdentity: buyerIdentity)
        var list = messagesByThreadKey[key] ?? []
        list.append(
            BuyerSellerThreadMessage(
                id: UUID(),
                text: trimmed,
                isFromBuyer: false,
                createdAt: Date(),
                buyerSenderName: nil
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

    func threadsForSellerOrderedByRecentMessage(sellerId: String) -> [SellerInboxThreadEntry] {
        let trimmedSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSellerId.isEmpty else { return [] }

        let matchingKeys = messagesByThreadKey.keys.filter { key in
            key.hasSuffix("|\(trimmedSellerId)")
        }

        return matchingKeys.sorted { lhs, rhs in
            let lhsDate = messagesByThreadKey[lhs]?.map(\.createdAt).max() ?? .distantPast
            let rhsDate = messagesByThreadKey[rhs]?.map(\.createdAt).max() ?? .distantPast
            return lhsDate > rhsDate
        }
        .compactMap { key in
            let components = key.components(separatedBy: "|")
            guard components.count == 2 else { return nil }
            let buyerIdentity = components[0]
            let messages = (messagesByThreadKey[key] ?? []).sorted { $0.createdAt < $1.createdAt }
            let lastMessage = messages.last
            let resolvedDisplayName = resolvedBuyerDisplayName(
                messages: messages,
                buyerIdentity: buyerIdentity
            )
            return SellerInboxThreadEntry(
                sellerId: trimmedSellerId,
                buyerIdentity: buyerIdentity,
                buyerDisplayName: resolvedDisplayName,
                lastMessageText: lastMessage?.text ?? "No messages yet",
                lastMessageTimestamp: lastMessage?.timestampLabel ?? "",
                lastMessageDate: lastMessage?.createdAt ?? .distantPast
            )
        }
    }

    /// Prefer a name captured when the buyer sent a message; fall back to identity-based label.
    private func resolvedBuyerDisplayName(messages: [BuyerSellerThreadMessage], buyerIdentity: String) -> String {
        if let named = messages.reversed().first(where: { message in
            guard message.isFromBuyer else { return false }
            let trimmed = message.buyerSenderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !trimmed.isEmpty
        }), let raw = named.buyerSenderName {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return buyerDisplayName(for: buyerIdentity)
    }

    private static func trimmedBuyerFullNameFromStorage() -> String? {
        let trimmed = UserDefaults.standard.string(forKey: "buyerFullName")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

    private func migrateLegacyGuestThreadKeysIfNeeded() {
        let newGuestKey = GuestInstallIdentity.userKey
        var next = messagesByThreadKey
        var changed = false
        for (key, value) in messagesByThreadKey {
            guard key.hasPrefix("guest|") else { continue }
            let suffix = String(key.dropFirst("guest".count))
            let newKey = "\(newGuestKey)\(suffix)"
            if next[newKey] == nil {
                next[newKey] = value
            }
            next.removeValue(forKey: key)
            changed = true
        }
        if changed {
            messagesByThreadKey = next
            save()
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

        return GuestInstallIdentity.userKey
    }

    private func threadKey(for sellerId: String) -> String {
        "\(currentBuyerIdentityKey)|\(sellerId)"
    }

    private func threadKey(for sellerId: String, buyerIdentity: String) -> String {
        "\(buyerIdentity)|\(sellerId)"
    }

    private func buyerDisplayName(for buyerIdentity: String) -> String {
        let defaults = UserDefaults.standard
        let storedName = defaults.string(forKey: "buyerFullName")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedEmail = defaults.string(forKey: "buyerEmail")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if buyerIdentity == "guest" || buyerIdentity.hasPrefix("guest:") {
            return "Guest buyer"
        }

        if buyerIdentity.hasPrefix("buyer:") {
            let email = String(buyerIdentity.dropFirst("buyer:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedEmail = email.lowercased()
            if !storedName.isEmpty, !storedEmail.isEmpty, storedEmail == normalizedEmail {
                return storedName
            }
            return email.isEmpty ? "Buyer" : email
        }

        return "Buyer"
    }
}

struct SellerInboxThreadEntry: Identifiable, Hashable {
    let sellerId: String
    let buyerIdentity: String
    let buyerDisplayName: String
    let lastMessageText: String
    let lastMessageTimestamp: String
    let lastMessageDate: Date

    var id: String { "\(buyerIdentity)|\(sellerId)" }
}

struct BuyerSellerThreadMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let isFromBuyer: Bool
    let createdAt: Date
    /// Snapshot of `buyerFullName` when the buyer sent this message (seller inbox can show this per thread).
    let buyerSenderName: String?

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
                createdAt: cal.date(byAdding: .hour, value: -2, to: base) ?? base,
                buyerSenderName: nil
            ),
            BuyerSellerThreadMessage(
                id: UUID(),
                text: "Yes — tell me which listing you want and I’ll confirm what’s in stock.",
                isFromBuyer: false,
                createdAt: cal.date(byAdding: .minute, value: -110, to: base) ?? base,
                buyerSenderName: nil
            ),
            BuyerSellerThreadMessage(
                id: UUID(),
                text: "Replies from \(sellerDisplayName) are usually within a few hours. This chat is only between you and this shop.",
                isFromBuyer: false,
                createdAt: cal.date(byAdding: .minute, value: -105, to: base) ?? base,
                buyerSenderName: nil
            )
        ]
    }
}
