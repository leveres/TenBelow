//
//  CatalogDecodePerformanceTests.swift
//  TenBelowTests
//

import XCTest
@testable import TenBelow

final class CatalogDecodePerformanceTests: XCTestCase {
    func testDecodeLargeSyntheticCatalogPerformance() throws {
        let products = (0..<400).map { index -> RemoteProduct in
            RemoteProduct(
                id: "perf-product-\(index)",
                sellerId: "seller_perf",
                name: "Performance sample \(index)",
                priceCents: 500 + (index % 5) * 100,
                category: "desk",
                imageURLs: [],
                demoVideoURL: nil,
                productionPreviewURL: nil,
                material: "PLA",
                durabilityNote: "Indoor use.",
                careWarnings: ["Avoid heat."],
                shipsInMinDays: 2,
                shipsInMaxDays: 4,
                isDrop: false,
                isActive: true,
                isApproved: true,
                averageRating: 4.5,
                reviewCount: 3,
                approvalStatus: "approved",
                archivedAt: nil,
                reviewNotes: nil,
                submittedAt: nil,
                previousPriceCents: nil,
                rightsOwnershipType: nil,
                rightsReferenceFlags: nil,
                rightsCertificationAccepted: nil,
                rightsCertificationAcceptedAt: nil,
                requiresManualReview: nil,
                reviewReason: nil
            )
        }

        let catalog = CatalogResponse(
            version: 1,
            updatedAt: "2026-04-24T00:00:00Z",
            products: products
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(catalog)

        measure {
            let decoder = JSONDecoder()
            _ = try? decoder.decode(CatalogResponse.self, from: data)
        }
    }
}
