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
}
