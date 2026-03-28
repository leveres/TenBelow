//
//  TenBelowUITests.swift
//  TenBelowUITests
//
//  Created by Steven  LeVere on 2/8/26.
//

import XCTest

final class TenBelowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testExample() throws {
        app.launch()
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testBuyerGuestCheckoutSmokeFlow() throws {
        app.launch()

        completeBuyerGuestEntryIfNeeded()

        XCTAssertTrue(app.staticTexts["Fresh favorites"].waitForExistence(timeout: 20))

        app.tabBars.buttons["Shop"].tap()
        XCTAssertTrue(app.textFields["Search products"].waitForExistence(timeout: 10))

        openAStorefrontProduct()

        for _ in 0..<4 {
            XCTAssertTrue(tapFirstAvailableControl(labels: ["Add to Cart", "Added"], timeout: 10))
        }

        let viewCartButton = app.buttons["View Cart"]
        XCTAssertTrue(viewCartButton.waitForExistence(timeout: 5))
        viewCartButton.tap()

        let proceedToCheckoutButton = app.buttons["Proceed to Checkout"]
        XCTAssertTrue(proceedToCheckoutButton.waitForExistence(timeout: 10))
        XCTAssertTrue(proceedToCheckoutButton.isEnabled)
        proceedToCheckoutButton.tap()

        XCTAssertTrue(app.staticTexts["Shipping Address"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Checkout unavailable"].exists)

        fillCheckoutField("Email", with: "smoke@example.com")
        fillCheckoutField("Full name", with: "Smoke Test")
        fillCheckoutField("Address", with: "1 Market St")
        fillCheckoutField("City", with: "San Francisco")
        fillCheckoutField("State", with: "CA")
        fillCheckoutField("ZIP", with: "94105")

        app.swipeUp()

        let acceptTermsButton = app.buttons["Accept terms"]
        XCTAssertTrue(acceptTermsButton.waitForExistence(timeout: 5))
        acceptTermsButton.tap()

        let payButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $20")).firstMatch
        XCTAssertTrue(payButton.waitForExistence(timeout: 10))
        XCTAssertTrue(payButton.isEnabled)
    }

    @MainActor
    private func completeBuyerGuestEntryIfNeeded() {
        tapControlIfPresent("I'm Shopping", timeout: 10)
        tapControlIfPresent("Continue as Guest", timeout: 10)
        tapControlIfPresent("Skip", timeout: 10)
    }

    @MainActor
    private func openAStorefrontProduct() {
        let preferredProductPredicate = NSPredicate(format: "label BEGINSWITH[c] %@", "Desk Cable Clip")
        let preferredLinks = app.links.matching(preferredProductPredicate)
        if preferredLinks.firstMatch.waitForExistence(timeout: 10) {
            preferredLinks.firstMatch.tap()
            return
        }

        let productPredicate = NSPredicate(format: "label CONTAINS %@", "$")
        let productLinks = app.links.matching(productPredicate)
        if productLinks.firstMatch.waitForExistence(timeout: 10) {
            productLinks.firstMatch.tap()
            return
        }

        let productButtons = app.buttons.matching(productPredicate)
        XCTAssertTrue(productButtons.firstMatch.waitForExistence(timeout: 10), "Expected at least one storefront product to appear.")
        productButtons.firstMatch.tap()
    }

    @MainActor
    private func fillCheckoutField(_ label: String, with value: String) {
        let field = app.textFields[label]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Missing checkout field: \(label)")
        field.tap()
        field.typeText(value)
    }

    @MainActor
    @discardableResult
    private func tapControlIfPresent(_ label: String, timeout: TimeInterval) -> Bool {
        let queries: [XCUIElement] = [
            app.buttons[label],
            app.staticTexts[label],
            app.links[label],
            app.otherElements[label]
        ]

        for element in queries where element.waitForExistence(timeout: timeout) {
            element.tap()
            return true
        }

        return false
    }

    @MainActor
    @discardableResult
    private func tapFirstAvailableControl(labels: [String], timeout: TimeInterval) -> Bool {
        for label in labels {
            if tapControlIfPresent(label, timeout: timeout) {
                return true
            }
        }

        return false
    }
}
