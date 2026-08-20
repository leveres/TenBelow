import XCTest
@testable import TenBelow

final class ProductColorOptionTests: XCTestCase {
    func testColorOptionNormalizesIDAndHex() {
        let color = ProductColorOption(name: " Ocean Blue ", hex: "3578c8")

        XCTAssertEqual(color.id, "ocean-blue")
        XCTAssertEqual(color.name, "Ocean Blue")
        XCTAssertEqual(color.hex, "#3578C8")
    }

    func testLegacyRemoteProductDecodesWithoutColors() throws {
        let payload = """
        {
          "id": "legacy",
          "sellerId": "seller",
          "name": "Legacy product",
          "priceCents": 500,
          "category": "desk",
          "imageURLs": [],
          "material": "PLA+",
          "durabilityNote": "Everyday use",
          "careWarnings": [],
          "shipsInMinDays": 2,
          "shipsInMaxDays": 4,
          "isDrop": false,
          "isActive": true,
          "isApproved": true
        }
        """

        let product = try JSONDecoder().decode(RemoteProduct.self, from: Data(payload.utf8))

        XCTAssertTrue(product.availableColors.isEmpty)
        XCTAssertTrue(product.asStorefrontProduct().availableColors.isEmpty)
    }

    func testCartLineIdentitySeparatesColors() {
        XCTAssertNotEqual(
            CartItem.lineID(productId: "product", selectedColorId: "black"),
            CartItem.lineID(productId: "product", selectedColorId: "white")
        )
        XCTAssertEqual(
            CartItem.lineID(productId: "product", selectedColorId: nil),
            "product"
        )
    }

    func testCheckoutItemEncodesSelectedColor() throws {
        let item = CheckoutItem(
            productId: "product",
            selectedColorId: "ocean-blue",
            quantity: 2
        )

        let data = try JSONEncoder().encode(item)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["selectedColorId"] as? String, "ocean-blue")
        XCTAssertEqual(object["quantity"] as? Int, 2)
    }
}
