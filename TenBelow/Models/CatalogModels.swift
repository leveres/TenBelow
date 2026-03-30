import Foundation

struct CatalogResponse: Codable {
    let version: Int
    let updatedAt: String
    let products: [RemoteProduct]
}

struct SellerProductResponse: Codable {
    let product: RemoteProduct
}

struct UpsertSellerProductRequest: Codable {
    let name: String
    let priceCents: Int
    let category: String
    let imageURLs: [String]
    let demoVideoURL: String?
    let material: String
    let durabilityNote: String
    let careWarnings: [String]
    let shipsInMinDays: Int
    let shipsInMaxDays: Int
    let isDrop: Bool
    let isActive: Bool
    let isApproved: Bool
}

enum DropType: String, Codable { case weekly, monthly }

struct AppConfig: Codable {
    let version: Int
    let freeShippingEnabled: Bool
    let minimumOrderCents: Int

    let dropEnabled: Bool
    let dropType: DropType
    let dropTitle: String
    let dropSubtitle: String
    let dropEndsAt: String
    let dropCta: String

    static let `default` = AppConfig(
        version: 2,
        freeShippingEnabled: true,
        minimumOrderCents: 1500,
        dropEnabled: true,
        dropType: .weekly,
        dropTitle: "Weekly Drop",
        dropSubtitle: "Premium prints • Limited run",
        dropEndsAt: "2026-02-23T05:00:00Z",
        dropCta: "View Drop"
    )
}

struct RemoteProduct: Codable, Identifiable, Hashable {
    let id: String
    let sellerId: String
    let name: String
    let priceCents: Int
    let category: String
    let imageURLs: [String]
    let demoVideoURL: String?
    let material: String
    let durabilityNote: String
    let careWarnings: [String]
    let shipsInMinDays: Int
    let shipsInMaxDays: Int
    let isDrop: Bool
    let isActive: Bool
    let isApproved: Bool
}

extension RemoteProduct {
    func asStorefrontProduct(fallbackProduct: Product? = nil) -> Product {
        Product(
            id: id,
            sellerId: sellerId,
            name: name,
            priceCents: priceCents,
            category: resolvedCategory,
            imageNames: imageURLs.isEmpty ? (fallbackProduct?.imageNames ?? ["products_image"]) : imageURLs,
            demoVideoURL: demoVideoURL.flatMap(URL.init(string:)),
            productionPreviewURL: fallbackProduct?.productionPreviewURL,
            pageViewCount: fallbackProduct?.pageViewCount ?? 0,
            favoriteCount: fallbackProduct?.favoriteCount ?? 0,
            material: material,
            productionNote: fallbackProduct?.productionNote ?? "Printed fresh when you order",
            durabilityNote: durabilityNote,
            careWarnings: careWarnings,
            shipsInDays: min(shipsInMinDays, shipsInMaxDays)...max(shipsInMinDays, shipsInMaxDays)
        )
    }

    private var resolvedCategory: Category {
        switch category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "home":
            return .home
        case "desk":
            return .desk
        case "car":
            return .car
        case "tech":
            return .tech
        case "gifts":
            return .gifts
        case "didn't know i needed this", "didnt know i needed this":
            return .didntKnow
        default:
            return fallbackCategory
        }
    }

    private var fallbackCategory: Category {
        fallbackProductCategoryOrder.first ?? .home
    }

    private var fallbackProductCategoryOrder: [Category] {
        Category.allCases.filter { $0.rawValue.caseInsensitiveCompare(category) == .orderedSame }
    }
}

func resolvedStorefrontProducts(remoteProducts: [RemoteProduct], fallbackProducts: [Product]) -> [Product] {
    let fallbackById = Dictionary(uniqueKeysWithValues: fallbackProducts.map { ($0.id, $0) })
    let fallbackBySeller = Dictionary(
        grouping: fallbackProducts,
        by: \.sellerId
    ).compactMapValues { $0.first }

    let mappedRemoteProducts = remoteProducts.map { remoteProduct in
        remoteProduct.asStorefrontProduct(
            fallbackProduct: fallbackById[remoteProduct.id] ?? fallbackBySeller[remoteProduct.sellerId]
        )
    }

    return mappedRemoteProducts.isEmpty ? fallbackProducts : mappedRemoteProducts
}
