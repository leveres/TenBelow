//
//  AppConstantsHostSmokeTests.swift
//  TenBelowTests
//
//  Runs in-process with `TenBelow` as `TEST_HOST` so `Bundle.main` is the app bundle.
//

import XCTest
@testable import TenBelow

final class AppConstantsHostSmokeTests: XCTestCase {
    func testMinimumOrderIsPositive() {
        XCTAssertGreaterThan(AppConstants.minimumOrderCents, 0)
    }

    func testTestingModeDefaultsKeyIsStable() {
        XCTAssertEqual(AppConstants.testingModeUserDefaultsKey, "tb.testingModeEnabled")
    }

    func testStripePublishableKeyFormatWhenPresent() {
        let key = AppConstants.stripePublishableKey
        if !key.isEmpty {
            XCTAssertTrue(key.hasPrefix("pk_"), "Stripe publishable keys must start with pk_")
        }
    }
}
