import Foundation

struct ShopProductComposerDraft: Codable {
    var draft: SellerProductDraft
    var updatedAt: Date
}

struct WeeklyDropComposerDraft: Codable {
    var draft: WeeklyDropDraft
    var stageRawValue: Int
    var isCreateMode: Bool
    var editProductId: String?
    var updatedAt: Date
}

enum SellerProductComposerDraftStore {
    private static func shopKey(for sellerId: String) -> String {
        "seller.shopComposerDraft.\(sellerId.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private static func weeklyDropKey(for sellerId: String) -> String {
        "seller.weeklyDropComposerDraft.\(sellerId.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func loadShop(sellerId: String) -> ShopProductComposerDraft? {
        let key = shopKey(for: sellerId)
        guard !sellerId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ShopProductComposerDraft.self, from: data)
    }

    static func saveShop(draft: SellerProductDraft) {
        let sellerId = draft.sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sellerId.isEmpty else { return }
        guard draft.hasComposerProgress else {
            clearShop(sellerId: sellerId)
            return
        }
        LocalCodableStore.save(
            ShopProductComposerDraft(draft: draft, updatedAt: Date()),
            key: shopKey(for: sellerId)
        )
    }

    static func clearShop(sellerId: String) {
        let trimmed = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        LocalCodableStore.remove(key: shopKey(for: trimmed))
    }

    static func loadWeeklyDrop(sellerId: String) -> WeeklyDropComposerDraft? {
        let key = weeklyDropKey(for: sellerId)
        guard !sellerId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WeeklyDropComposerDraft.self, from: data)
    }

    static func saveWeeklyDrop(
        draft: WeeklyDropDraft,
        stageRawValue: Int,
        isCreateMode: Bool,
        editProductId: String? = nil
    ) {
        let sellerId = draft.sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sellerId.isEmpty else { return }
        guard draft.hasComposerProgress else {
            clearWeeklyDrop(sellerId: sellerId)
            return
        }
        LocalCodableStore.save(
            WeeklyDropComposerDraft(
                draft: draft,
                stageRawValue: stageRawValue,
                isCreateMode: isCreateMode,
                editProductId: editProductId,
                updatedAt: Date()
            ),
            key: weeklyDropKey(for: sellerId)
        )
    }

    static func clearWeeklyDrop(sellerId: String) {
        let trimmed = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        LocalCodableStore.remove(key: weeklyDropKey(for: trimmed))
    }
}

extension SellerProductDraft {
    var hasComposerProgress: Bool {
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !imageURLStrings.isEmpty { return true }
        if !demoVideoURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !productionPreviewURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !material.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !durabilityNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !careWarningsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if rightsOwnershipType != nil || rightsCertificationAccepted { return true }
        if productionNote != "Printed fresh when you order",
           !productionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if shipsInMinDays != 2 || shipsInMaxDays != 4 { return true }
        return false
    }
}

extension WeeklyDropDraft {
    var hasComposerProgress: Bool {
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !bestUseCase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !imageURLStrings.isEmpty { return true }
        if !demoVideoURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !productionPreviewURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !material.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !durabilityNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !careWarningsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if rightsOwnershipType != nil || rightsCertificationAccepted { return true }
        if shipsInMinDays != 2 || shipsInMaxDays != 4 { return true }
        return false
    }
}
