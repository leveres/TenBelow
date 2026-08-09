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
    let rightsOwnershipType: String?
    let rightsReferenceFlags: [String]
    let rightsCertificationAccepted: Bool
    let rightsCertificationAcceptedAt: Date?
    let requiresManualReview: Bool
    let reviewReason: String?
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
    let rightsOwnershipType: String?
    let rightsReferenceFlags: [String]?
    let rightsCertificationAccepted: Bool?
    let rightsCertificationAcceptedAt: String?
    let requiresManualReview: Bool?
    let reviewReason: String?
}

extension RemoteProduct {
    private enum CodingKeys: String, CodingKey {
        case id, sellerId, name, priceCents, category, imageURLs, demoVideoURL
        case productionPreviewURL, material, durabilityNote, careWarnings
        case shipsInMinDays, shipsInMaxDays, isDrop, isActive, isApproved
        case averageRating, reviewCount, approvalStatus, archivedAt, reviewNotes
        case submittedAt, previousPriceCents, rightsOwnershipType, rightsReferenceFlags
        case rightsCertificationAccepted, rightsCertificationAcceptedAt
        case requiresManualReview, reviewReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sellerId = try container.decode(String.self, forKey: .sellerId)
        name = try container.decode(String.self, forKey: .name)
        priceCents = try container.decode(Int.self, forKey: .priceCents)
        category = try container.decode(String.self, forKey: .category)
        imageURLs = try container.decode([String].self, forKey: .imageURLs)
        demoVideoURL = try container.decodeIfPresent(String.self, forKey: .demoVideoURL)
        productionPreviewURL = try container.decodeIfPresent(String.self, forKey: .productionPreviewURL)
        material = try container.decode(String.self, forKey: .material)
        durabilityNote = try container.decode(String.self, forKey: .durabilityNote)
        careWarnings = try container.decode([String].self, forKey: .careWarnings)
        shipsInMinDays = try container.decode(Int.self, forKey: .shipsInMinDays)
        shipsInMaxDays = try container.decode(Int.self, forKey: .shipsInMaxDays)
        isDrop = try container.decode(Bool.self, forKey: .isDrop)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        isApproved = try container.decode(Bool.self, forKey: .isApproved)
        averageRating = try container.decodeIfPresent(Double.self, forKey: .averageRating)
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount)
        approvalStatus = try container.decodeIfPresent(String.self, forKey: .approvalStatus)
        archivedAt = try container.decodeIfPresent(String.self, forKey: .archivedAt)
        reviewNotes = try container.decodeIfPresent(String.self, forKey: .reviewNotes)
        submittedAt = try container.decodeIfPresent(String.self, forKey: .submittedAt)
        previousPriceCents = try container.decodeIfPresent(Int.self, forKey: .previousPriceCents)
        rightsOwnershipType = try container.decodeIfPresent(String.self, forKey: .rightsOwnershipType)
        rightsReferenceFlags = try container.decodeIfPresent([String].self, forKey: .rightsReferenceFlags)
        rightsCertificationAccepted = try container.decodeIfPresent(Bool.self, forKey: .rightsCertificationAccepted)
        requiresManualReview = try container.decodeIfPresent(Bool.self, forKey: .requiresManualReview)
        reviewReason = try container.decodeIfPresent(String.self, forKey: .reviewReason)

        if let isoString = try? container.decode(String.self, forKey: .rightsCertificationAcceptedAt) {
            rightsCertificationAcceptedAt = isoString
        } else if let seconds = try? container.decode(Double.self, forKey: .rightsCertificationAcceptedAt) {
            let date = seconds > 978_307_200
                ? Date(timeIntervalSince1970: seconds)
                : Date(timeIntervalSinceReferenceDate: seconds)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            rightsCertificationAcceptedAt = formatter.string(from: date)
        } else {
            rightsCertificationAcceptedAt = nil
        }
    }
}

extension RemoteProduct {
    /// Same resolution as storefront images: absolute URLs, or `/media/...` against `AppConstants.backendBaseURL`.
    private static func resolvedMediaURLString(_ raw: String?) -> URL? {
        Product.mediaURL(for: raw)
    }

    private static func parsedISO8601Date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    func asStorefrontProduct(fallbackProduct: Product? = nil) -> Product {
        let createdAtDate =
            Self.parsedISO8601Date(submittedAt) ??
            fallbackProduct?.createdAt ??
            .now
        let rightsAcceptedAtDate = Self.parsedISO8601Date(rightsCertificationAcceptedAt)
        return Product(
            id: id,
            sellerId: sellerId,
            name: name,
            priceCents: priceCents,
            category: resolvedCategory,
            imageNames: Product.displayableMediaReferences(
                in: imageURLs.isEmpty ? (fallbackProduct?.imageNames ?? ["products_image"]) : imageURLs
            ),
            demoVideoURL: Self.resolvedMediaURLString(demoVideoURL),
            productionPreviewURL: Self.resolvedMediaURLString(productionPreviewURL) ?? fallbackProduct?.productionPreviewURL,
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
            previousPriceCents: previousPriceCents ?? fallbackProduct?.previousPriceCents,
            rightsOwnershipType: rightsOwnershipType ?? fallbackProduct?.rightsOwnershipType,
            rightsReferenceFlags: rightsReferenceFlags ?? fallbackProduct?.rightsReferenceFlags ?? [],
            rightsCertificationAccepted: rightsCertificationAccepted ?? fallbackProduct?.rightsCertificationAccepted ?? false,
            rightsCertificationAcceptedAt: rightsAcceptedAtDate ?? fallbackProduct?.rightsCertificationAcceptedAt,
            requiresManualReview: requiresManualReview ?? fallbackProduct?.requiresManualReview ?? false,
            reviewReason: reviewReason ?? fallbackProduct?.reviewReason
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

    let resolvedProducts = mappedRemoteProducts.isEmpty ? fallbackProducts : mappedRemoteProducts
    #if DEBUG
    return resolvedProducts
    #else
    return resolvedProducts.filter(CatalogSeedPolicy.isRealStorefrontProduct)
    #endif
}

// MARK: - Seed / mock catalog filtering

enum CatalogSeedPolicy {
    static let seedSellerIDs: Set<String> = ["seller_001", "seller_002"]
    static let bundledPlaceholderImageNames: Set<String> = [
        "products_image",
        "filament_image",
        "printer_image",
    ]

    static func isSeedSeller(_ sellerId: String) -> Bool {
        seedSellerIDs.contains(sellerId.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func hasUploadedMedia(in imageReferences: [String]) -> Bool {
        imageReferences.contains { reference in
            let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            if bundledPlaceholderImageNames.contains(trimmed) { return false }
            if trimmed.hasPrefix("/media/") { return true }
            if let url = Product.mediaURL(for: trimmed),
               let scheme = url.scheme?.lowercased(),
               ["http", "https"].contains(scheme) {
                return true
            }
            return false
        }
    }

    static func isRealStorefrontProduct(_ product: Product) -> Bool {
        !isSeedSeller(product.sellerId) && hasUploadedMedia(in: product.imageNames)
    }

    static func isRealDropProduct(_ product: DropProduct) -> Bool {
        !isSeedSeller(product.sellerId) && hasUploadedMedia(in: product.imageURLs)
    }

    /// Weekly Drop lineups must only include catalog rows explicitly enrolled via drop submission.
    static func isEnrolledWeeklyDropProduct(id: String, catalog: [RemoteProduct]) -> Bool {
        catalog.first(where: { $0.id == id })?.isDrop == true
    }
}
