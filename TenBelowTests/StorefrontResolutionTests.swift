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
