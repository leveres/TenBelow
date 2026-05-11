import Foundation

enum ExchangeReasonCode: String, Codable, CaseIterable, Identifiable {
    case damaged
    case defective
    case wrongItem = "wrong_item"
    case poorQuality = "poor_quality"
    case missingPart = "missing_part"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .damaged:
            return "Damaged item"
        case .defective:
            return "Defective item"
        case .wrongItem:
            return "Wrong item"
        case .poorQuality:
            return "Material flaw"
        case .missingPart:
            return "Missing part"
        case .other:
            return "Other issue"
        }
    }

    var helperText: String {
        switch self {
        case .damaged:
            return "The item arrived broken, cracked, or visibly damaged."
        case .defective:
            return "The item does not function as expected."
        case .wrongItem:
            return "You received a different item than the one ordered."
        case .poorQuality:
            return "The item arrived with a material or print-quality issue."
        case .missingPart:
            return "A required part or included piece is missing."
        case .other:
            return "Tell us clearly what went wrong."
        }
    }
}

enum ExchangeRequestedResolution: String, Codable, CaseIterable, Identifiable {
    case sameItemExchange = "same_item_exchange"

    var id: String { rawValue }

    var title: String { "Same item replacement" }
}

enum ExchangeRequestStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case submitted
    case awaitingBuyerProof = "awaiting_buyer_proof"
    case underReview = "under_review"
    case awaitingSellerResponse = "awaiting_seller_response"
    case approved
    case denied
    case replacementPreparing = "replacement_preparing"
    case replacementShipped = "replacement_shipped"
    case replacementDelivered = "replacement_delivered"
    case closed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft:
            return "Draft"
        case .submitted:
            return "Submitted"
        case .awaitingBuyerProof:
            return "Waiting for More Info"
        case .underReview:
            return "Under Review"
        case .awaitingSellerResponse:
            return "Awaiting Seller Response"
        case .approved:
            return "Approved"
        case .denied:
            return "Denied"
        case .replacementPreparing:
            return "Preparing Replacement"
        case .replacementShipped:
            return "Replacement Shipped"
        case .replacementDelivered:
            return "Delivered"
        case .closed:
            return "Closed"
        case .cancelled:
            return "Cancelled"
        }
    }

    var detailCopy: String {
        switch self {
        case .draft:
            return "Your request has not been submitted yet."
        case .submitted:
            return "We received your exchange request."
        case .awaitingBuyerProof:
            return "We still need proof before review can continue."
        case .underReview:
            return "Our team is reviewing the request now."
        case .awaitingSellerResponse:
            return "We are waiting on seller fulfillment context."
        case .approved:
            return "Your exchange was approved for the same item."
        case .denied:
            return "This request was denied."
        case .replacementPreparing:
            return "Your replacement is being prepared."
        case .replacementShipped:
            return "Your replacement is on the way."
        case .replacementDelivered:
            return "Your replacement was marked delivered."
        case .closed:
            return "This exchange case is complete."
        case .cancelled:
            return "This request was cancelled."
        }
    }

    var isTerminal: Bool {
        switch self {
        case .denied, .closed, .cancelled, .replacementDelivered:
            return true
        default:
            return false
        }
    }

    var isActive: Bool {
        switch self {
        case .submitted, .awaitingBuyerProof, .underReview, .awaitingSellerResponse, .approved, .replacementPreparing, .replacementShipped:
            return true
        default:
            return false
        }
    }

    var countsTowardExchangeLimit: Bool {
        switch self {
        case .approved, .replacementPreparing, .replacementShipped, .replacementDelivered, .closed:
            return true
        default:
            return false
        }
    }
}

enum ExchangeProofAssetType: String, Codable, CaseIterable, Identifiable {
    case image
    case video

    var id: String { rawValue }
}

enum ExchangeTimelineActorType: String, Codable, CaseIterable, Identifiable {
    case buyer
    case seller
    case admin
    case system

    var id: String { rawValue }
}

enum ExchangeTimelineEventType: String, Codable, CaseIterable, Identifiable {
    case requestCreated = "request_created"
    case requestSubmitted = "request_submitted"
    case proofUploaded = "proof_uploaded"
    case buyerMessage = "buyer_message"
    case sellerMessage = "seller_message"
    case adminReviewStarted = "admin_review_started"
    case requestApproved = "request_approved"
    case requestDenied = "request_denied"
    case replacementStarted = "replacement_started"
    case trackingAdded = "tracking_added"
    case replacementShipped = "replacement_shipped"
    case replacementDelivered = "replacement_delivered"
    case requestClosed = "request_closed"
    case requestCancelled = "request_cancelled"
    case adminOverride = "admin_override"
    case statusChanged = "status_changed"

    var id: String { rawValue }
}

struct ExchangeProofAsset: Identifiable, Codable, Hashable {
    let id: String
    var type: ExchangeProofAssetType
    var url: String
    var storagePath: String
    var thumbnailURL: String?
    var uploadedAt: Date
    var uploadedByUserId: String

    init(
        id: String = UUID().uuidString,
        type: ExchangeProofAssetType,
        url: String,
        storagePath: String,
        thumbnailURL: String? = nil,
        uploadedAt: Date = .now,
        uploadedByUserId: String
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.storagePath = storagePath
        self.thumbnailURL = thumbnailURL
        self.uploadedAt = uploadedAt
        self.uploadedByUserId = uploadedByUserId
    }
}

struct ExchangeTimelineEvent: Identifiable, Codable, Hashable {
    let id: String
    var type: ExchangeTimelineEventType
    var message: String
    var actorType: ExchangeTimelineActorType
    var actorId: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        type: ExchangeTimelineEventType,
        message: String,
        actorType: ExchangeTimelineActorType,
        actorId: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.type = type
        self.message = message
        self.actorType = actorType
        self.actorId = actorId
        self.createdAt = createdAt
    }
}

struct ExchangeRequest: Identifiable, Codable, Hashable {
    let id: String
    var orderId: String
    var orderItemId: String
    var buyerUserId: String
    var sellerUserId: String
    var productId: String
    var productTitle: String
    var productImageURL: String?
    var originalVariantSnapshot: [String: String]
    var reasonCode: ExchangeReasonCode
    var buyerExplanation: String
    var requestedResolution: ExchangeRequestedResolution
    var status: ExchangeRequestStatus
    var denialReason: String?
    var adminNotes: String?
    var sellerNotes: String?
    var buyerProofAssets: [ExchangeProofAsset]
    var buyerSubmittedAt: Date?
    var reviewedAt: Date?
    var approvedAt: Date?
    var deniedAt: Date?
    var replacementShippedAt: Date?
    var replacementDeliveredAt: Date?
    var closedAt: Date?
    var eligibilityCheckedAt: Date?
    var eligibleAtSubmission: Bool
    var eligibilityFailureReason: String?
    var exchangeNumberForOrder: Int
    var isAdminOverride: Bool
    var trackingNumber: String?
    var shippingCarrier: String?
    var replacementOrderId: String?
    var timelineEvents: [ExchangeTimelineEvent]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        orderId: String,
        orderItemId: String,
        buyerUserId: String,
        sellerUserId: String,
        productId: String,
        productTitle: String,
        productImageURL: String? = nil,
        originalVariantSnapshot: [String: String] = [:],
        reasonCode: ExchangeReasonCode,
        buyerExplanation: String,
        requestedResolution: ExchangeRequestedResolution = .sameItemExchange,
        status: ExchangeRequestStatus = .draft,
        denialReason: String? = nil,
        adminNotes: String? = nil,
        sellerNotes: String? = nil,
        buyerProofAssets: [ExchangeProofAsset] = [],
        buyerSubmittedAt: Date? = nil,
        reviewedAt: Date? = nil,
        approvedAt: Date? = nil,
        deniedAt: Date? = nil,
        replacementShippedAt: Date? = nil,
        replacementDeliveredAt: Date? = nil,
        closedAt: Date? = nil,
        eligibilityCheckedAt: Date? = nil,
        eligibleAtSubmission: Bool,
        eligibilityFailureReason: String? = nil,
        exchangeNumberForOrder: Int = 0,
        isAdminOverride: Bool = false,
        trackingNumber: String? = nil,
        shippingCarrier: String? = nil,
        replacementOrderId: String? = nil,
        timelineEvents: [ExchangeTimelineEvent] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.orderId = orderId
        self.orderItemId = orderItemId
        self.buyerUserId = buyerUserId
        self.sellerUserId = sellerUserId
        self.productId = productId
        self.productTitle = productTitle
        self.productImageURL = productImageURL
        self.originalVariantSnapshot = originalVariantSnapshot
        self.reasonCode = reasonCode
        self.buyerExplanation = buyerExplanation
        self.requestedResolution = requestedResolution
        self.status = status
        self.denialReason = denialReason
        self.adminNotes = adminNotes
        self.sellerNotes = sellerNotes
        self.buyerProofAssets = buyerProofAssets
        self.buyerSubmittedAt = buyerSubmittedAt
        self.reviewedAt = reviewedAt
        self.approvedAt = approvedAt
        self.deniedAt = deniedAt
        self.replacementShippedAt = replacementShippedAt
        self.replacementDeliveredAt = replacementDeliveredAt
        self.closedAt = closedAt
        self.eligibilityCheckedAt = eligibilityCheckedAt
        self.eligibleAtSubmission = eligibleAtSubmission
        self.eligibilityFailureReason = eligibilityFailureReason
        self.exchangeNumberForOrder = exchangeNumberForOrder
        self.isAdminOverride = isAdminOverride
        self.trackingNumber = trackingNumber
        self.shippingCarrier = shippingCarrier
        self.replacementOrderId = replacementOrderId
        self.timelineEvents = timelineEvents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum ExchangeEligibilityFailureCode: String, Codable, CaseIterable, Identifiable {
    case orderNotFound = "order_not_found"
    case unauthorized
    case notDelivered = "not_delivered"
    case outsideWindow = "outside_window"
    case alreadyExchanged = "already_exchanged"
    case activeExchangeExists = "active_exchange_exists"
    case unsupportedItemType = "unsupported_item_type"
    case orderIneligible = "order_ineligible"
    case sameItemOnly = "same_item_only"
    case proofRequired = "proof_required"

    var id: String { rawValue }
}

struct ExchangeEligibilityResult: Codable, Hashable {
    var isEligible: Bool
    var failureCode: ExchangeEligibilityFailureCode?
    var failureMessage: String?
    var exchangeEligibleUntil: Date?
    var exchangeCount: Int
    var needsAdminReview: Bool
    var allowedResolutionTypes: [ExchangeRequestedResolution]

    static let eligible = ExchangeEligibilityResult(
        isEligible: true,
        failureCode: nil,
        failureMessage: nil,
        exchangeEligibleUntil: nil,
        exchangeCount: 0,
        needsAdminReview: false,
        allowedResolutionTypes: [.sameItemExchange]
    )
}

struct ExchangeRequestDraft: Identifiable, Codable, Hashable {
    let id: String
    var orderId: String
    var orderItemId: String
    var reasonCode: ExchangeReasonCode?
    var buyerExplanation: String
    var localAssets: [ExchangeLocalDraftAsset]
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        orderId: String,
        orderItemId: String,
        reasonCode: ExchangeReasonCode? = nil,
        buyerExplanation: String = "",
        localAssets: [ExchangeLocalDraftAsset] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.orderId = orderId
        self.orderItemId = orderItemId
        self.reasonCode = reasonCode
        self.buyerExplanation = buyerExplanation
        self.localAssets = localAssets
        self.updatedAt = updatedAt
    }
}

struct ExchangeLocalDraftAsset: Identifiable, Codable, Hashable {
    let id: String
    var type: ExchangeProofAssetType
    var localFileURLString: String
    var thumbnailURLString: String?
    var uploadedAt: Date

    init(
        id: String = UUID().uuidString,
        type: ExchangeProofAssetType,
        localFileURLString: String,
        thumbnailURLString: String? = nil,
        uploadedAt: Date = .now
    ) {
        self.id = id
        self.type = type
        self.localFileURLString = localFileURLString
        self.thumbnailURLString = thumbnailURLString
        self.uploadedAt = uploadedAt
    }

    var localFileURL: URL? {
        URL(fileURLWithPath: localFileURLString)
    }

    var thumbnailURL: URL? {
        guard let thumbnailURLString else { return nil }
        return URL(fileURLWithPath: thumbnailURLString)
    }
}
