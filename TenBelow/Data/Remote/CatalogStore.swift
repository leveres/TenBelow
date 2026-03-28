import Foundation
import Combine

@MainActor
final class CatalogStore: ObservableObject {

    @Published private(set) var products: [RemoteProduct] = []
    @Published private(set) var sellerProfiles: [SellerProfile] = []
    @Published private(set) var config: AppConfig = .default
    @Published private(set) var isLoading = false
    @Published private(set) var lastLoadError: String?
    @Published private(set) var isUsingCachedData = false

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

        self.products = catalogResult.products.filter { $0.isActive && $0.isApproved }
        self.isUsingCachedData = !catalogResult.isFromRemote
        self.sellerProfiles = sellers
        self.config   = cfg

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
        if let index = sellerProfiles.firstIndex(where: { $0.id == profile.id }) {
            sellerProfiles[index] = profile
        } else {
            sellerProfiles.append(profile)
        }
        sellerProfiles.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func upsertRemoteProduct(_ product: RemoteProduct) {
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
    }
}
