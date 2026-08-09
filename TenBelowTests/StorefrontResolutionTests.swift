//
//  StorefrontResolutionTests.swift
//  TenBelowTests
//

import XCTest
@testable import TenBelow

final class StorefrontResolutionTests: XCTestCase {
    func testResolvedStorefrontFallsBackWhenRemoteEmpty() {
        let fallback = MockData.products
        let resolved = resolvedStorefrontProducts(remoteProducts: [], fallbackProducts: fallback)
        XCTAssertEqual(resolved.count, fallback.count)
        XCTAssertEqual(resolved.map(\.id), fallback.map(\.id))
    }

    func testCatalogSeedPolicyFiltersDemoSellers() {
        XCTAssertTrue(CatalogSeedPolicy.isSeedSeller("seller_001"))
        XCTAssertTrue(CatalogSeedPolicy.isSeedSeller("seller_002"))
        XCTAssertFalse(CatalogSeedPolicy.isSeedSeller("real-maker"))
    }

    func testRemoteProductDecodesLegacyNumericCertificationDate() throws {
        let payload = """
        {
          "id": "approved-product",
          "sellerId": "real-maker",
          "name": "Approved Product",
          "priceCents": 450,
          "category": "desk",
          "imageURLs": ["https://cdn.example.com/product.jpg"],
          "demoVideoURL": null,
          "productionPreviewURL": null,
          "material": "PETG",
          "durabilityNote": "Everyday use",
          "careWarnings": [],
          "shipsInMinDays": 2,
          "shipsInMaxDays": 4,
          "isDrop": false,
          "isActive": true,
          "isApproved": true,
          "rightsCertificationAcceptedAt": 807865623.079337
        }
        """

        let product = try JSONDecoder().decode(RemoteProduct.self, from: Data(payload.utf8))

        XCTAssertEqual(product.id, "approved-product")
        XCTAssertNotNil(product.rightsCertificationAcceptedAt)
        XCTAssertNotNil(product.asStorefrontProduct().rightsCertificationAcceptedAt)
    }

    func testPremiumStorefrontContentDerivesRealMetadata() {
        let seller = SellerProfile(
            id: "real-maker",
            displayName: "Real Maker",
            handle: "@realmaker",
            bio: "Useful prints.",
            avatarMediaReference: nil,
            bannerMediaReference: nil,
            location: "United States",
            shipsInDays: 1...2,
            materials: ["PLA+"],
            processingTime: "1 business day",
            productCount: 2,
            orderCount: 25,
            rating: 0,
            isVerified: true,
            joinedAt: .now
        )
        let products = [
            makeProduct(
                id: "desk-one",
                category: .desk,
                image: "https://cdn.example.com/desk-one.jpg",
                rating: 5.0,
                reviews: 6,
                hasClip: true
            ),
            makeProduct(
                id: "home-one",
                category: .home,
                image: "https://cdn.example.com/home-one.jpg",
                rating: 4.5,
                reviews: 4
            ),
        ]

        let content = PremiumStorefrontCardContent(
            seller: seller,
            products: products,
            isCurrentSeller: false
        )

        XCTAssertEqual(content.productCount, 2)
        XCTAssertEqual(content.thumbnailReferences.count, 2)
        XCTAssertEqual(content.categories, [.desk, .home])
        XCTAssertEqual(content.effectiveReviewCount, 10)
        XCTAssertEqual(content.effectiveRating, 4.8, accuracy: 0.001)
        XCTAssertTrue(content.isTopRated)
        XCTAssertTrue(content.isFastShipping)
        XCTAssertNotNil(content.creatorClipURL)
    }

    func testReplacingSellerAccountIDPreservesPublicHandle() {
        let profile = SellerProfile(
            id: "stale-handle-value",
            displayName: "Steven",
            handle: "@stege",
            bio: "Useful prints.",
            location: "United States",
            shipsInDays: 2...4,
            materials: ["PETG"],
            processingTime: "2 business days",
            productCount: 1,
            orderCount: 0,
            rating: 0,
            isVerified: false,
            joinedAt: .now
        )

        let reconciled = profile.replacingAccountID(with: "steven")

        XCTAssertEqual(reconciled.id, "steven")
        XCTAssertEqual(reconciled.displayName, "Steven")
        XCTAssertEqual(reconciled.handle, "@stege")
    }

    private func makeProduct(
        id: String,
        category: TenBelow.Category,
        image: String,
        rating: Double,
        reviews: Int,
        hasClip: Bool = false
    ) -> Product {
        Product(
            id: id,
            sellerId: "real-maker",
            name: id,
            priceCents: 1500,
            category: category,
            imageNames: [image],
            demoVideoURL: hasClip ? URL(string: "https://cdn.example.com/clip.mp4") : nil,
            pageViewCount: 0,
            favoriteCount: 0,
            averageRating: rating,
            reviewCount: reviews,
            material: "PLA+",
            productionNote: "Printed fresh",
            durabilityNote: "Indoor use",
            careWarnings: [],
            shipsInDays: 1...2
        )
    }
}
