import Foundation
import Combine

@MainActor
final class BuyerEngagementStore: ObservableObject {
    @Published private(set) var snapshotsByIdentity: [String: BuyerEngagementSnapshot]

    private let storageKey = "buyerEngagementStore.snapshots"
    private let eventStore: CommerceEventStore

    init(eventStore: CommerceEventStore) {
        self.eventStore = eventStore
        snapshotsByIdentity = LocalCodableStore.load(
            key: storageKey,
            default: [:]
        )
        migrateLegacyGuestSnapshotsIfNeeded()
    }

    var currentIdentityKey: String {
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

    var favoriteProductIDs: Set<String> {
        snapshot(for: currentIdentityKey).favoriteProductIDs
    }

    var followedSellerIDs: Set<String> {
        snapshot(for: currentIdentityKey).followedSellerIDs
    }

    func isProductFavorited(_ productId: String) -> Bool {
        favoriteProductIDs.contains(productId)
    }

    /// Buyers and guests may favorite any listing. Sellers may favorite other sellers’ products, but not their own.
    func canFavoriteProduct(_ product: Product) -> Bool {
        let role = UserDefaults.standard.string(forKey: "userRole") ?? ""
        guard role == "seller" else { return true }

        let mySellerId = UserDefaults.standard.string(forKey: "sellerSellerId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if mySellerId.isEmpty { return true }

        return product.sellerId != mySellerId
    }

    /// Show the heart when the user may favorite, or when removing an existing favorite (e.g. cleanup).
    func showsFavoriteButton(for product: Product) -> Bool {
        canFavoriteProduct(product) || isProductFavorited(product.id)
    }

    func isSellerFollowed(_ sellerId: String) -> Bool {
        followedSellerIDs.contains(sellerId)
    }

    @discardableResult
    func toggleFavorite(for product: Product) -> Bool {
        var activeSnapshot = snapshot(for: currentIdentityKey)
        let wasFavorited = activeSnapshot.favoriteProductIDs.contains(product.id)

        if wasFavorited {
            activeSnapshot.favoriteProductIDs.remove(product.id)
            mutateInteraction(for: product, in: &activeSnapshot, kind: .favorited)
            snapshotsByIdentity[currentIdentityKey] = activeSnapshot
            persist()

            eventStore.record(
                CommerceEvent(
                    kind: .productUnfavorited,
                    buyerIdentity: currentIdentityKey,
                    productId: product.id,
                    sellerId: product.sellerId
                )
            )
            return false
        }

        guard canFavoriteProduct(product) else { return false }

        activeSnapshot.favoriteProductIDs.insert(product.id)
        mutateInteraction(for: product, in: &activeSnapshot, kind: .favorited)
        snapshotsByIdentity[currentIdentityKey] = activeSnapshot
        persist()

        eventStore.record(
            CommerceEvent(
                kind: .productFavorited,
                buyerIdentity: currentIdentityKey,
                productId: product.id,
                sellerId: product.sellerId
            )
        )

        return true
    }

    @discardableResult
    func toggleFollow(sellerId: String) -> Bool {
        var activeSnapshot = snapshot(for: currentIdentityKey)
        let isNowFollowed: Bool

        if activeSnapshot.followedSellerIDs.contains(sellerId) {
            activeSnapshot.followedSellerIDs.remove(sellerId)
            isNowFollowed = false
        } else {
            activeSnapshot.followedSellerIDs.insert(sellerId)
            isNowFollowed = true
        }

        snapshotsByIdentity[currentIdentityKey] = activeSnapshot
        persist()

        eventStore.record(
            CommerceEvent(
                kind: isNowFollowed ? .sellerFollowed : .sellerUnfollowed,
                buyerIdentity: currentIdentityKey,
                sellerId: sellerId
            )
        )

        return isNowFollowed
    }

    func trackProductView(_ product: Product) {
        var activeSnapshot = snapshot(for: currentIdentityKey)
        mutateInteraction(for: product, in: &activeSnapshot, kind: .viewed, incrementsViewCount: true)
        snapshotsByIdentity[currentIdentityKey] = activeSnapshot
        persist()

        eventStore.record(
            CommerceEvent(
                kind: .productViewed,
                buyerIdentity: currentIdentityKey,
                productId: product.id,
                sellerId: product.sellerId
            )
        )
    }

    func trackAddToCart(_ product: Product) {
        var activeSnapshot = snapshot(for: currentIdentityKey)
        mutateInteraction(for: product, in: &activeSnapshot, kind: .addedToCart)
        snapshotsByIdentity[currentIdentityKey] = activeSnapshot
        persist()
    }

    func trackPurchase(products: [Product]) {
        guard !products.isEmpty else { return }
        var activeSnapshot = snapshot(for: currentIdentityKey)

        for product in products {
            mutateInteraction(for: product, in: &activeSnapshot, kind: .purchased)
        }

        snapshotsByIdentity[currentIdentityKey] = activeSnapshot
        persist()
    }

    func hasInteracted(with productId: String) -> Bool {
        snapshot(for: currentIdentityKey).productInteractions[productId] != nil
    }

    func hasPurchased(from sellerId: String) -> Bool {
        snapshot(for: currentIdentityKey)
            .productInteractions
            .values
            .contains { record in
                record.sellerId == sellerId && record.interactionKinds.contains(.purchased)
            }
    }

    private func snapshot(for identityKey: String) -> BuyerEngagementSnapshot {
        snapshotsByIdentity[identityKey] ?? .empty
    }

    private func mutateInteraction(
        for product: Product,
        in snapshot: inout BuyerEngagementSnapshot,
        kind: ProductInteractionKind,
        incrementsViewCount: Bool = false
    ) {
        var record = snapshot.productInteractions[product.id] ?? ProductInteractionRecord(
            productId: product.id,
            sellerId: product.sellerId
        )
        record.interactionKinds.insert(kind)
        if incrementsViewCount {
            record.viewCount += 1
        }
        record.lastInteractedAt = .now
        snapshot.productInteractions[product.id] = record
    }

    private func migrateLegacyGuestSnapshotsIfNeeded() {
        let newKey = GuestInstallIdentity.userKey
        guard snapshotsByIdentity["guest"] != nil else { return }
        if snapshotsByIdentity[newKey] == nil {
            snapshotsByIdentity[newKey] = snapshotsByIdentity["guest"]
        }
        snapshotsByIdentity.removeValue(forKey: "guest")
        persist()
    }

    private func persist() {
        LocalCodableStore.save(snapshotsByIdentity, key: storageKey)
    }
}
