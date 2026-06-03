import Foundation

struct SellerInquiryThread: Identifiable, Codable, Hashable {
    let id: String
    let sellerId: String
    let buyerEmail: String
    let buyerName: String?
    var messages: [OrderSupportMessage]
    let createdAt: Date
    let updatedAt: Date

    var lastMessage: OrderSupportMessage? {
        messages.sorted { $0.createdAt < $1.createdAt }.last
    }
}

struct SellerInquiryThreadResponse: Decodable {
    let sellerId: String
    let buyerEmail: String?
    let threadId: String?
    let messages: [OrderSupportMessage]
}

struct SellerInquiryThreadListResponse: Decodable {
    let threads: [SellerInquiryThread]
}

struct SellerInquiryMessagePostResponse: Decodable {
    let sellerId: String
    let buyerEmail: String
    let threadId: String
    let message: OrderSupportMessage
    let messages: [OrderSupportMessage]
}

struct SellerInquirySellerLookupResponse: Decodable {
    let sellerId: String
    let buyerEmail: String?
    let thread: SellerInquiryThread?
    let messages: [OrderSupportMessage]
}
