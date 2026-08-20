import Foundation

enum ProductInteractionKind: String, Codable, Hashable, CaseIterable {
    case viewed
    case favorited
    case addedToCart
    case purchased
}

struct ProductInteractionRecord: Codable, Hashable {
    let productId: String
    let sellerId: String
    var interactionKinds: Set<ProductInteractionKind>
    var viewCount: Int
    var lastInteractedAt: Date

    init(
        productId: String,
        sellerId: String,
        interactionKinds: Set<ProductInteractionKind> = [],
        viewCount: Int = 0,
        lastInteractedAt: Date = .now
    ) {
        self.productId = productId
        self.sellerId = sellerId
        self.interactionKinds = interactionKinds
        self.viewCount = viewCount
        self.lastInteractedAt = lastInteractedAt
    }
}

struct BuyerEngagementSnapshot: Codable, Hashable {
    var favoriteProductIDs: Set<String>
    var followedSellerIDs: Set<String>
    var productInteractions: [String: ProductInteractionRecord]

    static let empty = BuyerEngagementSnapshot(
        favoriteProductIDs: [],
        followedSellerIDs: [],
        productInteractions: [:]
    )
}

struct StoredProduct: Identifiable, Codable, Hashable {
    let id: String
    var sellerId: String
    var name: String
    var priceCents: Int
    var category: Category
    var imageNames: [String]
    var demoVideoURL: URL?
    var productionPreviewURL: URL?
    var pageViewCount: Int
    var favoriteCount: Int
    var material: String
    var availableColors: [ProductColorOption]
    var productionNote: String
    var durabilityNote: String
    var careWarnings: [String]
    var shipsInMinDays: Int
    var shipsInMaxDays: Int
    var createdAt: Date
    var updatedAt: Date
    var previousPriceCents: Int?
    var rightsOwnershipType: String?
    var rightsReferenceFlags: [String]
    var rightsCertificationAccepted: Bool
    var rightsCertificationAcceptedAt: Date?
    var requiresManualReview: Bool
    var reviewReason: String?

    enum CodingKeys: String, CodingKey {
        case id, sellerId, name, priceCents, category, imageNames, demoVideoURL, productionPreviewURL
        case pageViewCount, favoriteCount, material, availableColors, productionNote, durabilityNote, careWarnings
        case shipsInMinDays, shipsInMaxDays, createdAt, updatedAt, previousPriceCents
        case rightsOwnershipType, rightsReferenceFlags, rightsCertificationAccepted
        case rightsCertificationAcceptedAt, requiresManualReview, reviewReason
    }

    init(
        product: Product,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        previousPriceCents: Int? = nil
    ) {
        id = product.id
        sellerId = product.sellerId
        name = product.name
        priceCents = product.priceCents
        category = product.category
        imageNames = product.imageNames
        demoVideoURL = product.demoVideoURL
        productionPreviewURL = product.productionPreviewURL
        pageViewCount = product.pageViewCount
        favoriteCount = product.favoriteCount
        material = product.material
        availableColors = product.availableColors
        productionNote = product.productionNote
        durabilityNote = product.durabilityNote
        careWarnings = product.careWarnings
        shipsInMinDays = product.shipsInDays.lowerBound
        shipsInMaxDays = product.shipsInDays.upperBound
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.previousPriceCents = product.previousPriceCents ?? previousPriceCents
        rightsOwnershipType = product.rightsOwnershipType
        rightsReferenceFlags = product.rightsReferenceFlags
        rightsCertificationAccepted = product.rightsCertificationAccepted
        rightsCertificationAcceptedAt = product.rightsCertificationAcceptedAt
        requiresManualReview = product.requiresManualReview
        reviewReason = product.reviewReason
    }

    init(
        draft: SellerProductDraft,
        fallbackImageNames: [String],
        existing: StoredProduct?,
        now: Date = .now
    ) {
        let sanitizedPrice = max(draft.priceCents, 0)

        id = draft.id
        sellerId = draft.sellerId
        name = draft.name.isEmpty ? "Untitled Product" : draft.name
        priceCents = sanitizedPrice
        category = draft.category
        imageNames = Product.displayableMediaReferences(
            in: draft.imageURLStrings.isEmpty ? (existing?.imageNames ?? fallbackImageNames) : draft.imageURLStrings
        )
        demoVideoURL = URL(string: draft.demoVideoURLString) ?? existing?.demoVideoURL
        productionPreviewURL = URL(string: draft.productionPreviewURLString)
        pageViewCount = existing?.pageViewCount ?? 0
        favoriteCount = existing?.favoriteCount ?? 0
        material = draft.material.isEmpty ? "PLA+" : draft.material
        availableColors = draft.availableColors
        productionNote = draft.productionNote.isEmpty ? "Printed fresh when you order" : draft.productionNote
        durabilityNote = draft.durabilityNote.isEmpty ? "Built for everyday use." : draft.durabilityNote
        careWarnings = draft.warningLines.isEmpty ? ["Handle with care."] : draft.warningLines
        shipsInMinDays = min(draft.shipsInMinDays, draft.shipsInMaxDays)
        shipsInMaxDays = max(draft.shipsInMinDays, draft.shipsInMaxDays)
        createdAt = existing?.createdAt ?? now
        updatedAt = now
        if let existing, existing.priceCents != sanitizedPrice {
            previousPriceCents = existing.priceCents
        } else {
            previousPriceCents = existing?.previousPriceCents
        }
        rightsOwnershipType = draft.rightsOwnershipType
        rightsReferenceFlags = draft.rightsReferenceFlags
        rightsCertificationAccepted = draft.rightsCertificationAccepted
        rightsCertificationAcceptedAt = draft.rightsCertificationAcceptedAt
        requiresManualReview = draft.requiresManualReview
        reviewReason = draft.reviewReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sellerId = try container.decode(String.self, forKey: .sellerId)
        name = try container.decode(String.self, forKey: .name)
        priceCents = try container.decode(Int.self, forKey: .priceCents)
        category = try container.decode(Category.self, forKey: .category)
        imageNames = try container.decode([String].self, forKey: .imageNames)
        demoVideoURL = try container.decodeIfPresent(URL.self, forKey: .demoVideoURL)
        productionPreviewURL = try container.decodeIfPresent(URL.self, forKey: .productionPreviewURL)
        pageViewCount = try container.decode(Int.self, forKey: .pageViewCount)
        favoriteCount = try container.decode(Int.self, forKey: .favoriteCount)
        material = try container.decode(String.self, forKey: .material)
        availableColors = try container.decodeIfPresent([ProductColorOption].self, forKey: .availableColors) ?? []
        productionNote = try container.decode(String.self, forKey: .productionNote)
        durabilityNote = try container.decode(String.self, forKey: .durabilityNote)
        careWarnings = try container.decode([String].self, forKey: .careWarnings)
        shipsInMinDays = try container.decode(Int.self, forKey: .shipsInMinDays)
        shipsInMaxDays = try container.decode(Int.self, forKey: .shipsInMaxDays)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        previousPriceCents = try container.decodeIfPresent(Int.self, forKey: .previousPriceCents)
        rightsOwnershipType = try container.decodeIfPresent(String.self, forKey: .rightsOwnershipType)
        rightsReferenceFlags = try container.decodeIfPresent([String].self, forKey: .rightsReferenceFlags) ?? []
        rightsCertificationAccepted = try container.decodeIfPresent(Bool.self, forKey: .rightsCertificationAccepted) ?? false
        rightsCertificationAcceptedAt = try container.decodeIfPresent(Date.self, forKey: .rightsCertificationAcceptedAt)
        requiresManualReview = try container.decodeIfPresent(Bool.self, forKey: .requiresManualReview) ?? false
        reviewReason = try container.decodeIfPresent(String.self, forKey: .reviewReason)
    }

    var product: Product {
        Product(
            id: id,
            sellerId: sellerId,
            name: name,
            priceCents: priceCents,
            category: category,
            imageNames: imageNames,
            demoVideoURL: demoVideoURL,
            productionPreviewURL: productionPreviewURL,
            pageViewCount: pageViewCount,
            favoriteCount: favoriteCount,
            material: material,
            availableColors: availableColors,
            productionNote: productionNote,
            durabilityNote: durabilityNote,
            careWarnings: careWarnings,
            shipsInDays: shipsInMinDays...shipsInMaxDays,
            createdAt: createdAt,
            previousPriceCents: previousPriceCents,
            rightsOwnershipType: rightsOwnershipType,
            rightsReferenceFlags: rightsReferenceFlags,
            rightsCertificationAccepted: rightsCertificationAccepted,
            rightsCertificationAcceptedAt: rightsCertificationAcceptedAt,
            requiresManualReview: requiresManualReview,
            reviewReason: reviewReason
        )
    }
}

enum CommerceEventKind: String, Codable, Hashable {
    case productViewed
    case productFavorited
    case productUnfavorited
    case sellerFollowed
    case sellerUnfollowed
    case productCreated
    case productUpdated
    case productPriceChanged
    case orderPlaced
    case orderStatusUpdated
    case shipmentStatusUpdated
    case orderSupportRequestCreated
    case orderSupportRequestUpdated
    case orderSupportMessageSent
    case exchangeSubmitted
    case exchangeProofUploaded
    case exchangeStatusUpdated
}

struct CommerceEvent: Identifiable, Codable, Hashable {
    let id: String
    let kind: CommerceEventKind
    let createdAt: Date
    let buyerIdentity: String?
    let productId: String?
    let orderId: String?
    let shipmentId: String?
    let sellerId: String?
    let metadata: [String: String]

    init(
        id: String = UUID().uuidString,
        kind: CommerceEventKind,
        createdAt: Date = .now,
        buyerIdentity: String? = nil,
        productId: String? = nil,
        orderId: String? = nil,
        shipmentId: String? = nil,
        sellerId: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.buyerIdentity = buyerIdentity
        self.productId = productId
        self.orderId = orderId
        self.shipmentId = shipmentId
        self.sellerId = sellerId
        self.metadata = metadata
    }
}
