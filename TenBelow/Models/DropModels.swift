import Foundation

// MARK: - Drop Constants

enum DropConstants {
    static let minPriceCents = 1001
    static let maxSlotsPerSeller = 4
}

// MARK: - Submission Request

struct DropSubmissionRequest: Codable {
    let sellerId: String
    let name: String
    let priceCents: Int
    let category: String
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
    let material: String
    let durabilityNote: String
    let careWarnings: [String]
    let shipsInMinDays: Int
    let shipsInMaxDays: Int
    let submittedAt: String
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
