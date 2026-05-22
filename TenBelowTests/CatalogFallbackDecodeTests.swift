//
//  CatalogFallbackDecodeTests.swift
//  TenBelowTests
//

import XCTest
@testable import TenBelow

@MainActor
final class CatalogFallbackDecodeTests: XCTestCase {
    func testBundleCatalogFallbackDecodesNonEmpty() throws {
        let response = try XCTUnwrap(
            CacheStore.loadFromBundle(CatalogResponse.self, resource: AppConstants.catalogFallbackFile)
        )
        XCTAssertFalse(response.products.isEmpty, "Ship a non-empty `products_fallback.json` for offline storefront.")
    }

    func testCatalogLoadResultUsesFallbackWhenRemoteUnavailable() async throws {
        removeCatalogDiskCache()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImmediateHTTPFailureURLProtocol.self]
        let stubSession = URLSession(configuration: configuration)

        let result = await CatalogService.loadProducts(urlSession: stubSession)

        XCTAssertFalse(result.products.isEmpty, "Expected bundle fallback after stubbed remote failure.")
        XCTAssertFalse(result.isFromRemote, "Stubbed HTTP error should not count as remote success.")
    }

    private func removeCatalogDiskCache() {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppConstants.catalogCacheFile)
        try? FileManager.default.removeItem(at: url)
    }
}
