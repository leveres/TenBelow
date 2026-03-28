import Foundation

struct ShippingAddress: Codable {
    var name: String
    var line1: String
    var line2: String?
    var city: String
    var state: String
    var postalCode: String
    var country: String
}

struct CheckoutItem: Codable {
    let productId: String
    let quantity: Int
}

struct CreatePaymentIntentRequest: Codable {
    let email: String
    let shipping: ShippingAddress
    let items: [CheckoutItem]
}

struct CreatePaymentIntentResponse: Codable {
    let clientSecret: String
    let orderId: String
}

struct CheckoutAPIErrorResponse: Codable {
    let code: String?
    let error: String
    let productId: String?
    let minimumOrderCents: Int?
}
