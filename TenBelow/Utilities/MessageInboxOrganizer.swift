import Foundation

enum MessageInboxFilter: String, CaseIterable, Identifiable {
    case conversations = "Conversations"
    case unread = "Unread"
    case recent = "Recent"
    case all = "All"

    var id: String { rawValue }
}

enum MessageInboxOrganizer {
    static let recentWindow: TimeInterval = 30 * 24 * 60 * 60

    static func visibleEntries(
        _ entries: [MessagingInboxEntry],
        filter: MessageInboxFilter,
        owner: String,
        viewerIsBuyer: Bool
    ) -> [MessagingInboxEntry] {
        let hidden = hiddenIDs(owner: owner)
        let cutoff = Date().addingTimeInterval(-recentWindow)

        return entries.filter { entry in
            guard !hidden.contains(entry.id) else { return false }
            let isQuietOldOrder = !entry.hasConversation && entry.lastMessageDate < cutoff
            guard !isQuietOldOrder else { return false }

            switch filter {
            case .all:
                return true
            case .conversations:
                return entry.hasConversation
            case .unread:
                return isUnread(entry, viewerIsBuyer: viewerIsBuyer, owner: owner)
            case .recent:
                return entry.lastMessageDate >= cutoff
            }
        }
    }

    static func isUnread(
        _ entry: MessagingInboxEntry,
        viewerIsBuyer: Bool,
        owner: String
    ) -> Bool {
        guard entry.hasConversation, let lastSenderRole = entry.lastSenderRole else { return false }
        let fromOtherPerson = viewerIsBuyer
            ? lastSenderRole != "buyer"
            : lastSenderRole == "buyer"
        guard fromOtherPerson else { return false }
        let lastRead = lastReadDate(for: entry.id, owner: owner) ?? .distantPast
        return entry.lastMessageDate > lastRead
    }

    static func markRead(_ entryID: String, owner: String, at date: Date = Date()) {
        var dates = readDates(owner: owner)
        dates[entryID] = max(dates[entryID] ?? .distantPast, date)
        saveReadDates(dates, owner: owner)
    }

    static func hide(_ entryIDs: [String], owner: String) {
        var hidden = hiddenIDs(owner: owner)
        hidden.formUnion(entryIDs)
        saveHiddenIDs(hidden, owner: owner)
    }

    static func restoreHidden(owner: String) {
        UserDefaults.standard.removeObject(forKey: hiddenKey(owner))
    }

    static func hiddenCount(in entries: [MessagingInboxEntry], owner: String) -> Int {
        let hidden = hiddenIDs(owner: owner)
        return entries.filter { hidden.contains($0.id) }.count
    }

    static func oldEntryIDs(in entries: [MessagingInboxEntry]) -> [String] {
        let cutoff = Date().addingTimeInterval(-recentWindow)
        return entries
            .filter { $0.lastMessageDate < cutoff }
            .map(\.id)
    }

    private static func lastReadDate(for entryID: String, owner: String) -> Date? {
        readDates(owner: owner)[entryID]
    }

    private static func hiddenIDs(owner: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: hiddenKey(owner)) ?? [])
    }

    private static func saveHiddenIDs(_ ids: Set<String>, owner: String) {
        UserDefaults.standard.set(Array(ids), forKey: hiddenKey(owner))
    }

    private static func readDates(owner: String) -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: readKey(owner)),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func saveReadDates(_ dates: [String: Date], owner: String) {
        guard let data = try? JSONEncoder().encode(dates) else { return }
        UserDefaults.standard.set(data, forKey: readKey(owner))
    }

    private static func hiddenKey(_ owner: String) -> String {
        "tb.messageInbox.hidden.\(owner)"
    }

    private static func readKey(_ owner: String) -> String {
        "tb.messageInbox.read.\(owner)"
    }
}
