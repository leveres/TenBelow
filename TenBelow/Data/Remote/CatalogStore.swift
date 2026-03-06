import Foundation
import Combine

@MainActor
final class CatalogStore: ObservableObject {

    @Published private(set) var products: [RemoteProduct] = []
    @Published private(set) var config: AppConfig = .default
    @Published private(set) var isLoading = false

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

        let catalog = await fetchedProducts
        let cfg     = await fetchedConfig

        self.products = catalog.filter { $0.isActive && $0.isApproved }
        self.config   = cfg
        self.isLoading = false
    }
}
