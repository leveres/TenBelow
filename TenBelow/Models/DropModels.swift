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
    let material: String
    let durabilityNote: String
    let careWarnings: [String]
    let shipsInMinDays: Int
    let shipsInMaxDays: Int
}

// MARK: - Drop Product (returned from backend)

struct DropProduct: Codable, Identifiable, Hashable {
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
    let submittedAt: String
}

extension DropProduct {
    var primaryImageReference: String? {
        imageURLs.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
                    category: "Home",
                    imageURLs: [],
                    demoVideoURL: nil,
                    material: "PLA+",
                    durabilityNote: "Indoor-friendly with reinforced walls.",
                    careWarnings: ["Avoid prolonged direct heat."],
                    shipsInMinDays: 2,
                    shipsInMaxDays: 4,
                    submittedAt: "2026-03-08T12:00:00Z"
                ),
                DropProduct(
                    id: "preview-drop-2",
                    sellerId: sellerId,
                    name: "Desk Cable Dock",
                    priceCents: 1400,
                    category: "Office",
                    imageURLs: [],
                    demoVideoURL: nil,
                    material: "PETG",
                    durabilityNote: "Built for everyday desk use.",
                    careWarnings: ["Wipe clean with a dry cloth."],
                    shipsInMinDays: 1,
                    shipsInMaxDays: 3,
                    submittedAt: "2026-03-08T12:10:00Z"
                )
            ]
        )
    }
}
