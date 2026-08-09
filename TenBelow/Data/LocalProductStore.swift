import Foundation
import Combine

@MainActor
final class LocalProductStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var productsRevision = 0

    private let storageKey = "localProductStore.products"
    private let eventStore: CommerceEventStore
    private var storedProducts: [StoredProduct] = []

    init(eventStore: CommerceEventStore) {
        self.eventStore = eventStore
        let persisted = LocalCodableStore.load(
            key: storageKey,
            default: [StoredProduct]()
        )

        if persisted.isEmpty {
            #if DEBUG
            storedProducts = seedProductsFromMocks()
            #else
            storedProducts = []
            #endif
        } else {
            storedProducts = persisted
            #if !DEBUG
            storedProducts.removeAll { CatalogSeedPolicy.isSeedSeller($0.sellerId) }
            #endif
        }

        syncPersistedSellerDraftsIntoProducts()
        persist()
        refreshPublishedProducts()
    }

    func product(withId productId: String) -> Product? {
        storedProducts.first(where: { $0.id == productId })?.product
    }

    func products(for sellerId: String) -> [Product] {
        storedProducts
            .filter { $0.sellerId == sellerId }
            .map(\.product)
    }

    func registerProductView(for productId: String) {
        guard let index = storedProducts.firstIndex(where: { $0.id == productId }) else { return }
        storedProducts[index].pageViewCount += 1
        storedProducts[index].updatedAt = .now
        persist()
        refreshPublishedProducts()
    }

    func setFavoriteState(for productId: String, isFavorited: Bool) {
        guard let index = storedProducts.firstIndex(where: { $0.id == productId }) else { return }
        let delta = isFavorited ? 1 : -1
        storedProducts[index].favoriteCount = max(0, storedProducts[index].favoriteCount + delta)
        storedProducts[index].updatedAt = .now
        persist()
        refreshPublishedProducts()
    }

    func saveDraft(_ draft: SellerProductDraft) {
        let existing = storedProducts.first(where: { $0.id == draft.id })
        let updatedProduct = upsertStoredProduct(for: draft)
        persist()
        refreshPublishedProducts()
        recordEvents(for: updatedProduct, previous: existing)
    }

    func saveDrafts(_ drafts: [SellerProductDraft]) {
        guard !drafts.isEmpty else { return }

        var previousByID: [String: StoredProduct] = [:]
        var updatedProducts: [StoredProduct] = []
        for draft in drafts {
            previousByID[draft.id] = storedProducts.first(where: { $0.id == draft.id })
            updatedProducts.append(upsertStoredProduct(for: draft))
        }

        persist()
        refreshPublishedProducts()

        for updatedProduct in updatedProducts {
            recordEvents(for: updatedProduct, previous: previousByID[updatedProduct.id])
        }
    }

    func removeDraft(productId: String) {
        guard let index = storedProducts.firstIndex(where: { $0.id == productId }) else { return }
        storedProducts.remove(at: index)
        persist()
        refreshPublishedProducts()
    }

    private func seedProductsFromMocks() -> [StoredProduct] {
        MockData.products.enumerated().map { index, product in
            StoredProduct(
                product: product,
                createdAt: Date.now.addingTimeInterval(TimeInterval(-index)),
                updatedAt: Date.now.addingTimeInterval(TimeInterval(-index))
            )
        }
    }

    private func syncPersistedSellerDraftsIntoProducts() {
        let sellerIds = Set(storedProducts.map(\.sellerId))

        for sellerId in sellerIds {
            let storageKey = "sellerProductDraftsData.\(sellerId)"
            let drafts = LocalCodableStore.load(
                key: storageKey,
                default: [SellerProductDraft]()
            )

            guard !drafts.isEmpty else { continue }

            for draft in drafts {
                let existing = storedProducts.first(where: { $0.id == draft.id })
                let fallbackImageNames = fallbackImageNames(for: draft, existing: existing)
                let updatedProduct = StoredProduct(
                    draft: draft,
                    fallbackImageNames: fallbackImageNames,
                    existing: existing
                )

                if let existingIndex = storedProducts.firstIndex(where: { $0.id == draft.id }) {
                    storedProducts[existingIndex] = updatedProduct
                } else {
                    storedProducts.insert(updatedProduct, at: 0)
                }
            }
        }
    }

    @discardableResult
    private func upsertStoredProduct(for draft: SellerProductDraft) -> StoredProduct {
        let existing = storedProducts.first(where: { $0.id == draft.id })
        let updatedProduct = StoredProduct(
            draft: draft,
            fallbackImageNames: fallbackImageNames(for: draft, existing: existing),
            existing: existing
        )

        if let existingIndex = storedProducts.firstIndex(where: { $0.id == draft.id }) {
            storedProducts[existingIndex] = updatedProduct
        } else {
            storedProducts.insert(updatedProduct, at: 0)
        }

        return updatedProduct
    }

    private func fallbackImageNames(
        for draft: SellerProductDraft,
        existing: StoredProduct?
    ) -> [String] {
        if let existing, !existing.imageNames.isEmpty {
            return existing.imageNames
        }

        if let baseProduct = MockData.products.first(where: { $0.id == draft.id }),
           !baseProduct.imageNames.isEmpty {
            return baseProduct.imageNames
        }

        if let sellerProduct = MockData.products.first(where: { $0.sellerId == draft.sellerId }),
           !sellerProduct.imageNames.isEmpty {
            return sellerProduct.imageNames
        }

        return ["products_image"]
    }

    private func recordEvents(for updated: StoredProduct, previous: StoredProduct?) {
        if previous == nil {
            eventStore.record(
                CommerceEvent(
                    kind: .productCreated,
                    productId: updated.id,
                    sellerId: updated.sellerId,
                    metadata: [
                        "name": updated.name,
                        "priceCents": "\(updated.priceCents)"
                    ]
                )
            )
            return
        }

        if previous?.priceCents != updated.priceCents {
            eventStore.record(
                CommerceEvent(
                    kind: .productPriceChanged,
                    productId: updated.id,
                    sellerId: updated.sellerId,
                    metadata: [
                        "oldPriceCents": "\(previous?.priceCents ?? updated.priceCents)",
                        "newPriceCents": "\(updated.priceCents)"
                    ]
                )
            )
        }

        eventStore.record(
            CommerceEvent(
                kind: .productUpdated,
                productId: updated.id,
                sellerId: updated.sellerId
            )
        )
    }

    private func refreshPublishedProducts() {
        products = storedProducts.map(\.product)
        productsRevision &+= 1
    }

    private func persist() {
        LocalCodableStore.save(storedProducts, key: storageKey)
    }
}
