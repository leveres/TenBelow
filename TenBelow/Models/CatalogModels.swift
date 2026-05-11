import Foundation

struct CatalogResponse: Codable {
    let version: Int
    let updatedAt: String
    let products: [RemoteProduct]
}

struct SellerProductResponse: Codable {
    let product: RemoteProduct
}

struct SellerProductsListResponse: Codable {
    let products: [RemoteProduct]
}

struct UpsertSellerProductRequest: Codable {
    let name: String
    let priceCents: Int
    let category: String
    let imageURLs: [String]
    let demoVideoURL: String?
    let productionPreviewURL: String?
    let material: String
    let durabilityNote: String
    let careWarnings: [String]
    let shipsInMinDays: Int
    let shipsInMaxDays: Int
    let isDrop: Bool
    let isActive: Bool
    let isApproved: Bool
}

struct RemoveSellerProductRequest: Codable {
    let reason: String
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
    let exchangeWindowDays: Int
    let maxExchangeCountPerOrderItem: Int
    let minProofImages: Int
    let maxProofImages: Int
    let allowProofVideo: Bool
    let maxVideoDurationSeconds: Int
    let requireAdminForApproval: Bool

    static let `default` = AppConfig(
        version: 2,
        freeShippingEnabled: true,
        minimumOrderCents: 1500,
        dropEnabled: true,
        dropType: .weekly,
        dropTitle: "Weekly Drop",
        dropSubtitle: "Premium prints • Limited run",
        dropEndsAt: "2026-02-23T05:00:00Z",
        dropCta: "View Drop",
        exchangeWindowDays: 7,
        maxExchangeCountPerOrderItem: 1,
        minProofImages: 1,
        maxProofImages: 5,
        allowProofVideo: true,
        maxVideoDurationSeconds: 15,
        requireAdminForApproval: true
    )

    enum CodingKeys: String, CodingKey {
        case version
        case freeShippingEnabled
        case minimumOrderCents
        case dropEnabled
        case dropType
        case dropTitle
        case dropSubtitle
        case dropEndsAt
        case dropCta
        case exchangeWindowDays
        case maxExchangeCountPerOrderItem
        case minProofImages
        case maxProofImages
        case allowProofVideo
        case maxVideoDurationSeconds
        case requireAdminForApproval
    }

    init(
        version: Int,
        freeShippingEnabled: Bool,
        minimumOrderCents: Int,
        dropEnabled: Bool,
        dropType: DropType,
        dropTitle: String,
        dropSubtitle: String,
        dropEndsAt: String,
        dropCta: String,
        exchangeWindowDays: Int,
        maxExchangeCountPerOrderItem: Int,
        minProofImages: Int,
        maxProofImages: Int,
        allowProofVideo: Bool,
        maxVideoDurationSeconds: Int,
        requireAdminForApproval: Bool
    ) {
        self.version = version
        self.freeShippingEnabled = freeShippingEnabled
        self.minimumOrderCents = minimumOrderCents
        self.dropEnabled = dropEnabled
        self.dropType = dropType
        self.dropTitle = dropTitle
        self.dropSubtitle = dropSubtitle
        self.dropEndsAt = dropEndsAt
        self.dropCta = dropCta
        self.exchangeWindowDays = exchangeWindowDays
        self.maxExchangeCountPerOrderItem = maxExchangeCountPerOrderItem
        self.minProofImages = minProofImages
        self.maxProofImages = maxProofImages
        self.allowProofVideo = allowProofVideo
        self.maxVideoDurationSeconds = maxVideoDurationSeconds
        self.requireAdminForApproval = requireAdminForApproval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig.default
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? defaults.version
        freeShippingEnabled = try container.decodeIfPresent(Bool.self, forKey: .freeShippingEnabled) ?? defaults.freeShippingEnabled
        minimumOrderCents = try container.decodeIfPresent(Int.self, forKey: .minimumOrderCents) ?? defaults.minimumOrderCents
        dropEnabled = try container.decodeIfPresent(Bool.self, forKey: .dropEnabled) ?? defaults.dropEnabled
        dropType = try container.decodeIfPresent(DropType.self, forKey: .dropType) ?? defaults.dropType
        dropTitle = try container.decodeIfPresent(String.self, forKey: .dropTitle) ?? defaults.dropTitle
        dropSubtitle = try container.decodeIfPresent(String.self, forKey: .dropSubtitle) ?? defaults.dropSubtitle
        dropEndsAt = try container.decodeIfPresent(String.self, forKey: .dropEndsAt) ?? defaults.dropEndsAt
        dropCta = try container.decodeIfPresent(String.self, forKey: .dropCta) ?? defaults.dropCta
        exchangeWindowDays = try container.decodeIfPresent(Int.self, forKey: .exchangeWindowDays) ?? defaults.exchangeWindowDays
        maxExchangeCountPerOrderItem = try container.decodeIfPresent(Int.self, forKey: .maxExchangeCountPerOrderItem) ?? defaults.maxExchangeCountPerOrderItem
        minProofImages = try container.decodeIfPresent(Int.self, forKey: .minProofImages) ?? defaults.minProofImages
        maxProofImages = try container.decodeIfPresent(Int.self, forKey: .maxProofImages) ?? defaults.maxProofImages
        allowProofVideo = try container.decodeIfPresent(Bool.self, forKey: .allowProofVideo) ?? defaults.allowProofVideo
        maxVideoDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .maxVideoDurationSeconds) ?? defaults.maxVideoDurationSeconds
        requireAdminForApproval = try container.decodeIfPresent(Bool.self, forKey: .requireAdminForApproval) ?? defaults.requireAdminForApproval
    }
}

struct RemoteProduct: Codable, Identifiable, Hashable {
    let id: String
    let sellerId: String
    let name: String
    let priceCents: Int
    let category: String
    let imageURLs: [String]
    let demoVideoURL: String?
    let productionPreviewURL: String?
    let material: String
    let durabilityNote: String
    let careWarnings: [String]
    let shipsInMinDays: Int
    let shipsInMaxDays: Int
    let isDrop: Bool
    let isActive: Bool
    let isApproved: Bool
    let averageRating: Double?
    let reviewCount: Int?
    /// Server marketplace workflow (`submitted`, `approved`, `rejected`, `archived`).
    let approvalStatus: String?
    let archivedAt: String?
    let reviewNotes: String?
    let submittedAt: String?
    let previousPriceCents: Int?
}

extension RemoteProduct {
    func asStorefrontProduct(fallbackProduct: Product? = nil) -> Product {
        let formatter = ISO8601DateFormatter()
        let createdAtDate =
            submittedAt.flatMap { formatter.date(from: $0) } ??
            fallbackProduct?.createdAt ??
            .now
        return Product(
            id: id,
            sellerId: sellerId,
            name: name,
            priceCents: priceCents,
            category: resolvedCategory,
            imageNames: imageURLs.isEmpty ? (fallbackProduct?.imageNames ?? ["products_image"]) : imageURLs,
            demoVideoURL: demoVideoURL.flatMap(URL.init(string:)),
            productionPreviewURL: productionPreviewURL.flatMap(URL.init(string:)) ?? fallbackProduct?.productionPreviewURL,
            pageViewCount: fallbackProduct?.pageViewCount ?? 0,
            favoriteCount: fallbackProduct?.favoriteCount ?? 0,
            averageRating: averageRating ?? fallbackProduct?.averageRating ?? 0,
            reviewCount: reviewCount ?? fallbackProduct?.reviewCount ?? 0,
            material: material,
            productionNote: fallbackProduct?.productionNote ?? "Printed fresh when you order",
            durabilityNote: durabilityNote,
            careWarnings: careWarnings,
            shipsInDays: min(shipsInMinDays, shipsInMaxDays)...max(shipsInMinDays, shipsInMaxDays),
            createdAt: createdAtDate,
            previousPriceCents: previousPriceCents ?? fallbackProduct?.previousPriceCents
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
