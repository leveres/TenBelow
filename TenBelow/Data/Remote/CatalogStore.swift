import Foundation
import Combine

@MainActor
final class CatalogStore: ObservableObject {

    @Published private(set) var products: [RemoteProduct] = []
    @Published private(set) var sellerProfiles: [SellerProfile] = []
    @Published private(set) var config: AppConfig = .default
    @Published private(set) var contentRevision = 0
    @Published private(set) var isLoading = false
    @Published private(set) var lastLoadError: String?
    @Published private(set) var isUsingCachedData = false
    private let eventStore: CommerceEventStore?

    init(eventStore: CommerceEventStore? = nil) {
        self.eventStore = eventStore
    }

    // MARK: - Filtered Views

    var dropProducts: [RemoteProduct] {
        products.filter { $0.isDrop }
    }

    func products(for category: String) -> [RemoteProduct] {
        products.filter { $0.category == category }
    }

    // MARK: - Load

    func load() async {
        isLoading = true

        async let fetchedProducts = CatalogService.loadProducts()
        async let fetchedConfig   = ConfigService.loadConfig()
        async let fetchedSellerProfiles = loadSellerProfiles()

        let catalogResult = await fetchedProducts
        let cfg     = await fetchedConfig
        let sellers = await fetchedSellerProfiles

        let previousProducts = products
        let visibleProducts = catalogResult.products.filter { $0.isActive && $0.isApproved }
        self.products = visibleProducts
        self.isUsingCachedData = !catalogResult.isFromRemote
        self.sellerProfiles = sellers
        self.config   = cfg
        contentRevision &+= 1
        if catalogResult.isFromRemote {
            recordCatalogEvents(previous: previousProducts, next: visibleProducts, sellers: sellers)
        }

        if catalogResult.isFromRemote {
            lastLoadError = nil
        } else if products.isEmpty {
            lastLoadError = "Couldn't reach the server. Check your connection."
        } else {
            lastLoadError = "Showing saved products until the latest catalog is available."
        }

        self.isLoading = false
    }

    private func loadSellerProfiles() async -> [SellerProfile] {
        do {
            return try await SellerAPI.fetchProfiles()
        } catch {
            return sellerProfiles
        }
    }

    func upsertSellerProfile(_ profile: SellerProfile) {
        var next = sellerProfiles
        if let index = next.firstIndex(where: { $0.id == profile.id }) {
            next[index] = profile
        } else {
            next.append(profile)
        }
        next.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        sellerProfiles = next
        contentRevision &+= 1
    }

    func upsertRemoteProduct(_ product: RemoteProduct) {
        let previousProducts = products
        if let index = products.firstIndex(where: { $0.id == product.id }) {
            products[index] = product
        } else {
            products.insert(product, at: 0)
        }
        products = products
            .filter { $0.isActive && $0.isApproved }
            .sorted { lhs, rhs in
                if lhs.sellerId == rhs.sellerId {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.sellerId.localizedCaseInsensitiveCompare(rhs.sellerId) == .orderedAscending
            }
        contentRevision &+= 1
        recordCatalogEvents(previous: previousProducts, next: products, sellers: sellerProfiles)
    }

    private func recordCatalogEvents(
        previous: [RemoteProduct],
        next: [RemoteProduct],
        sellers: [SellerProfile]
    ) {
        guard let eventStore else { return }

        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let sellersByID = Dictionary(uniqueKeysWithValues: sellers.map { ($0.id, $0) })

        for product in next {
            let previousProduct = previousByID[product.id]
            let sellerName = sellersByID[product.sellerId]?.displayName ?? product.sellerId

            if previousProduct == nil {
                eventStore.record(
                    CommerceEvent(
                        kind: .productCreated,
                        productId: product.id,
                        sellerId: product.sellerId,
                        metadata: [
                            "name": product.name,
                            "priceCents": "\(product.priceCents)",
                            "sellerName": sellerName
                        ]
                    )
                )
                continue
            }

            if previousProduct?.priceCents != product.priceCents {
                eventStore.record(
                    CommerceEvent(
                        kind: .productPriceChanged,
                        productId: product.id,
                        sellerId: product.sellerId,
                        metadata: [
                            "name": product.name,
                            "sellerName": sellerName,
                            "oldPriceCents": "\(previousProduct?.priceCents ?? product.priceCents)",
                            "newPriceCents": "\(product.priceCents)"
                        ]
                    )
                )
            }

            let previousMakerVideo = previousProduct?.productionPreviewURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let nextMakerVideo = product.productionPreviewURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if previousMakerVideo.isEmpty, !nextMakerVideo.isEmpty {
                eventStore.record(
                    CommerceEvent(
                        kind: .productUpdated,
                        productId: product.id,
                        sellerId: product.sellerId,
                        metadata: [
                            "name": product.name,
                            "sellerName": sellerName,
                            "update": "makerVideoReady"
                        ]
                    )
                )
            }
        }
    }
}
