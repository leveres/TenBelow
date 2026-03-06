import Foundation

struct CatalogResponse: Codable {
    let version: Int
    let updatedAt: String
    let products: [RemoteProduct]
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
        minimumOrderCents: 2000,
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
