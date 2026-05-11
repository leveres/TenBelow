//
//  ExchangeModelTests.swift
//  TenBelowTests
//

import XCTest
@testable import TenBelow

final class ExchangeModelTests: XCTestCase {
    func testExchangeReasonCodeTitlesAreNonEmpty() {
        for code in ExchangeReasonCode.allCases {
            XCTAssertFalse(code.title.isEmpty, code.rawValue)
            XCTAssertFalse(code.helperText.isEmpty, code.rawValue)
        }
    }

    func testExchangeRequestJSONRoundTrip() throws {
        let original = ExchangeRequest(
            id: "ex-1",
            orderId: "ord-1",
            orderItemId: "li-1",
            buyerUserId: "buyer-1",
            sellerUserId: "seller-1",
            productId: "prod-1",
            productTitle: "Test item",
            reasonCode: .damaged,
            buyerExplanation: "Arrived cracked.",
            status: .submitted,
            eligibleAtSubmission: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExchangeRequest.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.orderId, original.orderId)
        XCTAssertEqual(decoded.reasonCode, original.reasonCode)
        XCTAssertEqual(decoded.status, original.status)
    }
}
