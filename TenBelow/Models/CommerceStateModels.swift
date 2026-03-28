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
    var productionNote: String
    var durabilityNote: String
    var careWarnings: [String]
    var shipsInMinDays: Int
    var shipsInMaxDays: Int
    var createdAt: Date
    var updatedAt: Date
    var previousPriceCents: Int?

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
        productionNote = product.productionNote
        durabilityNote = product.durabilityNote
        careWarnings = product.careWarnings
        shipsInMinDays = product.shipsInDays.lowerBound
        shipsInMaxDays = product.shipsInDays.upperBound
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.previousPriceCents = previousPriceCents
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
        imageNames = draft.imageURLStrings.isEmpty ? (existing?.imageNames ?? fallbackImageNames) : draft.imageURLStrings
        demoVideoURL = URL(string: draft.demoVideoURLString) ?? existing?.demoVideoURL
        productionPreviewURL = URL(string: draft.productionPreviewURLString)
        pageViewCount = existing?.pageViewCount ?? 0
        favoriteCount = existing?.favoriteCount ?? 0
        material = draft.material.isEmpty ? "PLA+" : draft.material
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
            productionNote: productionNote,
            durabilityNote: durabilityNote,
            careWarnings: careWarnings,
            shipsInDays: shipsInMinDays...shipsInMaxDays
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
