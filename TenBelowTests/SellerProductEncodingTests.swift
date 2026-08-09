import XCTest
@testable import TenBelow

final class SellerProductEncodingTests: XCTestCase {
    func testSellerProductCertificationDateEncodesAsISO8601String() throws {
        let acceptedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-08T07:00:00Z")
        )
        let request = UpsertSellerProductRequest(
            name: "Toothbrush storage case",
            priceCents: 450,
            category: "desk",
            imageURLs: [],
            demoVideoURL: nil,
            productionPreviewURL: nil,
            material: "PETG",
            durabilityNote: "Built for everyday use.",
            careWarnings: ["Handle with care."],
            shipsInMinDays: 2,
            shipsInMaxDays: 4,
            isDrop: false,
            isActive: false,
            isApproved: false,
            rightsOwnershipType: "original",
            rightsReferenceFlags: [],
            rightsCertificationAccepted: true,
            rightsCertificationAcceptedAt: acceptedAt,
            requiresManualReview: false,
            reviewReason: nil
        )

        let data = try SellerAPI.encodeSellerProductRequest(request)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(
            object["rightsCertificationAcceptedAt"] as? String,
            "2026-08-08T07:00:00Z"
        )
    }
}
