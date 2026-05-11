//
//  TenBelowUITests.swift
//  TenBelowUITests
//
//  Created by Steven  LeVere on 2/8/26.
//
//  Launch arguments (DEBUG, applied in `AppConstants.applyLaunchArgumentsForTesting()`):
//  - `-UIEnableTestingMode` — relaxed checkout / API (matches Settings → Developer).
//

import XCTest

final class TenBelowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-UIEnableTestingMode",
        ]
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testGuestAuthAndHomeSmoke() throws {
        app.launch()
        completeBuyerGuestEntryIfNeeded()
        XCTAssertTrue(app.staticTexts["Fresh favorites"].waitForExistence(timeout: 25))
    }

    @MainActor
    func testShopCatalogLoadsSmoke() throws {
        app.launch()
        completeBuyerGuestEntryIfNeeded()
        XCTAssertTrue(app.tabBars.buttons["Shop"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Shop"].tap()

        let searchById = app.textFields["shop.search.field"]
        let searchByLabel = app.textFields["Search products"]
        XCTAssertTrue(
            searchById.waitForExistence(timeout: 12) || searchByLabel.waitForExistence(timeout: 4),
            "Shop search field should appear after catalog load."
        )

        let hasGrid = app.scrollViews.firstMatch.waitForExistence(timeout: 12)
        let hasEmptyCopy = app.staticTexts["No products to show"].waitForExistence(timeout: 2)
        XCTAssertTrue(hasGrid || hasEmptyCopy, "Expected either a product grid or an explicit empty state.")
    }

    @MainActor
    func testOrdersPullToRefreshSmoke() throws {
        app.launch()
        completeBuyerGuestEntryIfNeeded()

        XCTAssertTrue(app.tabBars.buttons["Orders"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Orders"].tap()

        XCTAssertTrue(
            app.staticTexts["No orders yet"].waitForExistence(timeout: 15)
                || app.staticTexts["Your purchases and delivery updates."].waitForExistence(timeout: 15)
        )

        let scroll = app.scrollViews["orders.empty.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        scroll.swipeDown(velocity: .fast)
    }

    @MainActor
    func testLegalTermsFromSettingsSmoke() throws {
        app.launch()
        completeBuyerGuestEntryIfNeeded()

        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Settings"].tap()

        app.staticTexts["View terms of service"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Terms of Service"].waitForExistence(timeout: 12))
        let legalRoot = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", "legal.document.termsOfService")
        ).firstMatch
        XCTAssertTrue(legalRoot.waitForExistence(timeout: 8))

        let settingsBack = app.navigationBars.buttons["Settings"]
        if settingsBack.waitForExistence(timeout: 3) {
            settingsBack.tap()
        } else if app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 2) {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    @MainActor
    func testBuyerGuestCheckoutSmokeFlow() throws {
        app.launch()

        completeBuyerGuestEntryIfNeeded()

        XCTAssertTrue(app.staticTexts["Fresh favorites"].waitForExistence(timeout: 20))

        app.tabBars.buttons["Shop"].tap()
        let shopSearch = app.textFields["shop.search.field"]
        let shopSearchFallback = app.textFields["Search products"]
        XCTAssertTrue(
            shopSearch.waitForExistence(timeout: 10) || shopSearchFallback.waitForExistence(timeout: 4),
            "Shop search field missing."
        )

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

        let payById = app.buttons["checkout.pay"]
        let payByPrefix = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay $")).firstMatch
        XCTAssertTrue(payById.waitForExistence(timeout: 10) || payByPrefix.waitForExistence(timeout: 4))
        let payButton = payById.exists ? payById : payByPrefix
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
        let identifier = checkoutFieldAccessibilityIdentifier(for: label)
        let byId = app.textFields[identifier]
        if byId.waitForExistence(timeout: 3) {
            byId.tap()
            byId.typeText(value)
            return
        }
        let byLabel = app.textFields[label]
        XCTAssertTrue(byLabel.waitForExistence(timeout: 10), "Missing checkout field: \(label) / \(identifier)")
        byLabel.tap()
        byLabel.typeText(value)
    }

    private func checkoutFieldAccessibilityIdentifier(for label: String) -> String {
        switch label {
        case "Email": return "checkout.field.email"
        case "Full name": return "checkout.field.fullName"
        case "Address": return "checkout.field.addressLine1"
        case "Apt, suite (optional)": return "checkout.field.addressLine2"
        case "City": return "checkout.field.city"
        case "State": return "checkout.field.state"
        case "ZIP": return "checkout.field.postalCode"
        case "Country": return "checkout.field.country"
        default: return label
        }
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
