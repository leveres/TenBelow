import Foundation

enum OrderSupportRequestType: String, Codable, CaseIterable, Identifiable {
    case cancel
    case refund

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cancel: return "Cancel order"
        case .refund: return "Refund request"
        }
    }
}

enum OrderSupportRequestStatus: String, Codable {
    case pending
    case approved
    case denied
    case withdrawn

    var title: String {
        switch self {
        case .pending: return "Pending"
        case .approved: return "Approved"
        case .denied: return "Denied"
        case .withdrawn: return "Withdrawn"
        }
    }
}

struct SupportEvidenceAsset: Identifiable, Codable, Hashable {
    let id: String
    var type: String
    var url: String
    var uploadedAt: Date

    var isVideo: Bool { type == "video" }
}

struct OrderSupportRequest: Identifiable, Codable, Hashable {
    let id: String
    var type: OrderSupportRequestType
    var status: OrderSupportRequestStatus
    var sellerId: String
    var shipmentId: String?
    var reason: String
    var requestedBy: String
    var resolutionNote: String?
    var evidenceAssets: [SupportEvidenceAsset]?
    var createdAt: Date
    var updatedAt: Date
}

struct OrderSupportMessage: Identifiable, Codable, Hashable {
    let id: String
    var sellerId: String
    var senderRole: String
    var senderEmail: String?
    var senderName: String?
    var text: String
    var createdAt: Date

    var isFromBuyer: Bool { senderRole == "buyer" }

    var timestampLabel: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

struct OrderSupportThreadResponse: Decodable {
    let orderId: String
    let sellerId: String
    let messages: [OrderSupportMessage]
}

struct OrderSupportMessagePostResponse: Decodable {
    let orderId: String
    let sellerId: String
    let message: OrderSupportMessage
    let messages: [OrderSupportMessage]
    let order: Order?
}
