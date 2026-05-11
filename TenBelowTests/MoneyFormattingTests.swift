//
//  MoneyFormattingTests.swift
//  TenBelowTests
//

import XCTest
@testable import TenBelow

final class MoneyFormattingTests: XCTestCase {
    func testFormatZeroCents() {
        let formatted = Money.format(cents: 0)
        XCTAssertFalse(formatted.isEmpty)
        XCTAssertTrue(formatted.contains("0"), "Expected a zero amount in the formatted string: \(formatted)")
    }

    func testFormatTypicalPrice() {
        XCTAssertTrue(Money.format(cents: 1000).contains("10"))
        XCTAssertTrue(Money.format(cents: 499).contains("4"))
        XCTAssertTrue(Money.format(cents: 499).contains("9"))
    }

    func testDollarsFromCents() {
        XCTAssertEqual(Money.dollars(fromCents: 1500), 15.0, accuracy: 0.0001)
    }
}
