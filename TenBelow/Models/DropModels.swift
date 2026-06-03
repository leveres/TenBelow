import Foundation

// MARK: - Drop Constants

enum DropConstants {
    static let minPriceCents = 1001
    static let maxSlotsPerSeller = 4
}

// MARK: - Submission Request

struct DropSubmissionRequest: Codable {
    let productId: String
    let sellerId: String
    let name: String
    let priceCents: Int
    let category: String
    let imageURLs: [String]
    let demoVideoURL: String?
    let productionPreviewURL: String?
    let headline: String
    let story: String
    let bestUseCase: String
    let material: String
    let durabilityNote: String
    let careWarnings: [String]
    let shipsInMinDays: Int
    let shipsInMaxDays: Int
    let rightsOwnershipType: String?
    let rightsReferenceFlags: [String]
    let rightsCertificationAccepted: Bool
    let rightsCertificationAcceptedAt: Date?
    let requiresManualReview: Bool
    let reviewReason: String?
}

enum WeeklyDropSubmissionStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case ready
    case submitted
    case approved
    case rejected
    case archived
    case live

    var id: String { rawValue }
}

// MARK: - Drop Product (returned from backend)

struct DropProduct: Codable, Identifiable, Hashable {
    let id: String
    let sellerId: String
    let name: String
    let priceCents: Int
    let previousPriceCents: Int?
    let category: String
    let imageURLs: [String]
    let demoVideoURL: String?
    let productionPreviewURL: String?
    let headline: String
    let story: String
    let bestUseCase: String
    let material: String
    let durabilityNote: String
    let careWarnings: [String]
    let shipsInMinDays: Int
    let shipsInMaxDays: Int
    let approvalStatus: WeeklyDropSubmissionStatus
    let reviewNotes: String?
    let reviewedAt: String?
    let submittedAt: String
    let slotNumber: Int?
    var rightsOwnershipType: String? = nil
    var rightsReferenceFlags: [String]? = nil
    var rightsCertificationAccepted: Bool? = nil
    var rightsCertificationAcceptedAt: String? = nil
    var requiresManualReview: Bool? = nil
    var reviewReason: String? = nil
}

extension DropProduct {
    var primaryImageReference: String? {
        imageURLs.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var displayHeadline: String {
        if !headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return headline
        }
        if !story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return story
        }
        return durabilityNote
    }
}

// MARK: - Current Drop Response

struct CurrentDropResponse: Codable {
    let active: Bool
    let weekId: String
    let startsAt: String
    let endsAt: String
    let products: [DropProduct]
    let nextDropAt: String?
}

// MARK: - Seller Submissions Response

struct SellerSubmissionsResponse: Codable {
    let sellerId: String
    let weekId: String
    let isActive: Bool
    let nextDropAt: String?
    let slotsUsed: Int
    let slotsMax: Int
    let products: [DropProduct]
}

struct SellerDropHistoryWeek: Codable, Identifiable, Hashable {
    let weekId: String
    let startsAt: String
    let endsAt: String
    let postedCount: Int
    let soldCount: Int
    let products: [DropProduct]

    var id: String { weekId }
}

struct SellerDropHistoryResponse: Codable {
    let sellerId: String
    let weeks: [SellerDropHistoryWeek]
}

// MARK: - Delete Response

struct DropDeleteResponse: Codable {
    let deleted: Bool
    let product: DropProduct
}

extension SellerSubmissionsResponse {
    static func preview(sellerId: String) -> SellerSubmissionsResponse {
        SellerSubmissionsResponse(
            sellerId: sellerId,
            weekId: "preview-week",
            isActive: true,
            nextDropAt: nil,
            slotsUsed: 2,
            slotsMax: DropConstants.maxSlotsPerSeller,
            products: [
                DropProduct(
                    id: "preview-drop-1",
                    sellerId: sellerId,
                    name: "Textured Planter",
                    priceCents: 1800,
                    previousPriceCents: nil,
                    category: "Home",
                    imageURLs: [],
                    demoVideoURL: nil,
                    productionPreviewURL: nil,
                    headline: "A sculptural desktop accent for Friday's lineup.",
                    story: "Designed as a limited-run planter with layered texture and a softer matte finish.",
                    bestUseCase: "Perfect for styling desks, side tables, or entry shelves.",
                    material: "PLA+",
                    durabilityNote: "Indoor-friendly with reinforced walls.",
                    careWarnings: ["Avoid prolonged direct heat."],
                    shipsInMinDays: 2,
                    shipsInMaxDays: 4,
                    approvalStatus: .approved,
                    reviewNotes: nil,
                    reviewedAt: "2026-03-08T18:00:00Z",
                    submittedAt: "2026-03-08T12:00:00Z",
                    slotNumber: 1
                ),
                DropProduct(
                    id: "preview-drop-2",
                    sellerId: sellerId,
                    name: "Desk Cable Dock",
                    priceCents: 1400,
                    previousPriceCents: nil,
                    category: "Office",
                    imageURLs: [],
                    demoVideoURL: nil,
                    productionPreviewURL: nil,
                    headline: "A compact cable tray tuned for smaller work setups.",
                    story: "Built as a Friday-exclusive desk accessory with a cleaner, more minimal profile.",
                    bestUseCase: "Use it to organize charging cables on nightstands and desks.",
                    material: "PETG",
                    durabilityNote: "Built for everyday desk use.",
                    careWarnings: ["Wipe clean with a dry cloth."],
                    shipsInMinDays: 1,
                    shipsInMaxDays: 3,
                    approvalStatus: .submitted,
                    reviewNotes: nil,
                    reviewedAt: nil,
                    submittedAt: "2026-03-08T12:10:00Z",
                    slotNumber: 2
                )
            ]
        )
    }
}

struct WeeklyDropDraft: Identifiable, Codable, Hashable {
    let id: String
    var sellerId: String
    var name: String
    var headline: String
    var priceText: String
    var category: Category
    var story: String
    var bestUseCase: String
    var imageURLStrings: [String]
    var demoVideoURLString: String
    var productionPreviewURLString: String
    var material: String
    var durabilityNote: String
    var careWarningsText: String
    var shipsInMinDays: Int
    var shipsInMaxDays: Int
    var rightsOwnershipType: String?
    var rightsReferenceFlags: [String] = []
    var rightsCertificationAccepted: Bool = false
    var rightsCertificationAcceptedAt: Date?
    var requiresManualReview: Bool = false
    var reviewReason: String?

    enum CodingKeys: String, CodingKey {
        case id, sellerId, name, headline, priceText, category, story, bestUseCase
        case imageURLStrings, demoVideoURLString, productionPreviewURLString
        case material, durabilityNote, careWarningsText, shipsInMinDays, shipsInMaxDays
        case rightsOwnershipType, rightsReferenceFlags, rightsCertificationAccepted
        case rightsCertificationAcceptedAt, requiresManualReview, reviewReason
    }

    init(
        id: String,
        sellerId: String,
        name: String,
        headline: String,
        priceText: String,
        category: Category,
        story: String,
        bestUseCase: String,
        imageURLStrings: [String],
        demoVideoURLString: String,
        productionPreviewURLString: String,
        material: String,
        durabilityNote: String,
        careWarningsText: String,
        shipsInMinDays: Int,
        shipsInMaxDays: Int,
        rightsOwnershipType: String? = nil,
        rightsReferenceFlags: [String] = [],
        rightsCertificationAccepted: Bool = false,
        rightsCertificationAcceptedAt: Date? = nil,
        requiresManualReview: Bool = false,
        reviewReason: String? = nil
    ) {
        self.id = id
        self.sellerId = sellerId
        self.name = name
        self.headline = headline
        self.priceText = priceText
        self.category = category
        self.story = story
        self.bestUseCase = bestUseCase
        self.imageURLStrings = imageURLStrings
        self.demoVideoURLString = demoVideoURLString
        self.productionPreviewURLString = productionPreviewURLString
        self.material = material
        self.durabilityNote = durabilityNote
        self.careWarningsText = careWarningsText
        self.shipsInMinDays = shipsInMinDays
        self.shipsInMaxDays = shipsInMaxDays
        self.rightsOwnershipType = rightsOwnershipType
        self.rightsReferenceFlags = rightsReferenceFlags
        self.rightsCertificationAccepted = rightsCertificationAccepted
        self.rightsCertificationAcceptedAt = rightsCertificationAcceptedAt
        self.requiresManualReview = requiresManualReview
        self.reviewReason = reviewReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sellerId = try container.decode(String.self, forKey: .sellerId)
        name = try container.decode(String.self, forKey: .name)
        headline = try container.decode(String.self, forKey: .headline)
        priceText = try container.decode(String.self, forKey: .priceText)
        category = try container.decode(Category.self, forKey: .category)
        story = try container.decode(String.self, forKey: .story)
        bestUseCase = try container.decode(String.self, forKey: .bestUseCase)
        imageURLStrings = try container.decode([String].self, forKey: .imageURLStrings)
        demoVideoURLString = try container.decode(String.self, forKey: .demoVideoURLString)
        productionPreviewURLString = try container.decode(String.self, forKey: .productionPreviewURLString)
        material = try container.decode(String.self, forKey: .material)
        durabilityNote = try container.decode(String.self, forKey: .durabilityNote)
        careWarningsText = try container.decode(String.self, forKey: .careWarningsText)
        shipsInMinDays = try container.decode(Int.self, forKey: .shipsInMinDays)
        shipsInMaxDays = try container.decode(Int.self, forKey: .shipsInMaxDays)
        rightsOwnershipType = try container.decodeIfPresent(String.self, forKey: .rightsOwnershipType)
        rightsReferenceFlags = try container.decodeIfPresent([String].self, forKey: .rightsReferenceFlags) ?? []
        rightsCertificationAccepted = try container.decodeIfPresent(Bool.self, forKey: .rightsCertificationAccepted) ?? false
        rightsCertificationAcceptedAt = try container.decodeIfPresent(Date.self, forKey: .rightsCertificationAcceptedAt)
        requiresManualReview = try container.decodeIfPresent(Bool.self, forKey: .requiresManualReview) ?? false
        reviewReason = try container.decodeIfPresent(String.self, forKey: .reviewReason)
    }

    static func new(sellerId: String) -> WeeklyDropDraft {
        WeeklyDropDraft(
            id: "drop-\(UUID().uuidString)",
            sellerId: sellerId,
            name: "",
            headline: "",
            priceText: "",
            category: .home,
            story: "",
            bestUseCase: "",
            imageURLStrings: [],
            demoVideoURLString: "",
            productionPreviewURLString: "",
            material: "",
            durabilityNote: "",
            careWarningsText: "",
            shipsInMinDays: 2,
            shipsInMaxDays: 4
        )
    }

    init(product: DropProduct) {
        id = product.id
        sellerId = product.sellerId
        name = product.name
        headline = product.headline
        priceText = String(format: "%.2f", Double(product.priceCents) / 100.0)
        category = Category(rawValue: product.category) ?? .home
        story = product.story
        bestUseCase = product.bestUseCase
        imageURLStrings = product.imageURLs
        demoVideoURLString = product.demoVideoURL ?? ""
        productionPreviewURLString = product.productionPreviewURL ?? ""
        material = product.material
        durabilityNote = product.durabilityNote
        careWarningsText = product.careWarnings.joined(separator: "\n")
        shipsInMinDays = product.shipsInMinDays
        shipsInMaxDays = product.shipsInMaxDays
        let formatter = ISO8601DateFormatter()
        rightsOwnershipType = product.rightsOwnershipType
        rightsReferenceFlags = product.rightsReferenceFlags ?? []
        rightsCertificationAccepted = product.rightsCertificationAccepted ?? false
        rightsCertificationAcceptedAt = product.rightsCertificationAcceptedAt.flatMap { formatter.date(from: $0) }
        requiresManualReview = product.requiresManualReview ?? false
        reviewReason = product.reviewReason
    }

    var priceCents: Int {
        Int((Double(priceText) ?? 0) * 100)
    }

    var careWarnings: [String] {
        careWarningsText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isReadyForSubmission: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && priceCents >= DropConstants.minPriceCents
            && !story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !imageURLStrings.isEmpty
            && !material.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isRightsConfirmationComplete
    }

    var isRightsConfirmationComplete: Bool {
        rightsOwnershipType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && !rightsReferenceFlags.isEmpty
            && rightsCertificationAccepted
    }

    mutating func refreshRightsReviewFlag() {
        requiresManualReview = ProductRightsReview.requiresManualReview(
            ownershipType: rightsOwnershipType,
            referenceFlags: rightsReferenceFlags
        )
        reviewReason = ProductRightsReview.reviewReason(referenceFlags: rightsReferenceFlags)
    }

    var submissionRequest: DropSubmissionRequest {
        DropSubmissionRequest(
            productId: id,
            sellerId: sellerId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            priceCents: priceCents,
            category: category.rawValue,
            imageURLs: imageURLStrings,
            demoVideoURL: demoVideoURLString.nilIfBlank,
            productionPreviewURL: productionPreviewURLString.nilIfBlank,
            headline: headline.trimmingCharacters(in: .whitespacesAndNewlines),
            story: story.trimmingCharacters(in: .whitespacesAndNewlines),
            bestUseCase: bestUseCase.trimmingCharacters(in: .whitespacesAndNewlines),
            material: material.trimmingCharacters(in: .whitespacesAndNewlines),
            durabilityNote: durabilityNote.trimmingCharacters(in: .whitespacesAndNewlines),
            careWarnings: careWarnings,
            shipsInMinDays: min(shipsInMinDays, shipsInMaxDays),
            shipsInMaxDays: max(shipsInMinDays, shipsInMaxDays),
            rightsOwnershipType: rightsOwnershipType,
            rightsReferenceFlags: rightsReferenceFlags,
            rightsCertificationAccepted: rightsCertificationAccepted,
            rightsCertificationAcceptedAt: rightsCertificationAcceptedAt,
            requiresManualReview: requiresManualReview,
            reviewReason: reviewReason
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
