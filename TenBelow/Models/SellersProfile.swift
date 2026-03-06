import Foundation

struct SellerProfile: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let handle: String
    let bio: String
    let avatarURL: URL?
    let bannerURL: URL?
    let websiteURL: URL?
    let location: String
    let shipsInDays: ClosedRange<Int>
    let materials: [String]
    let processingTime: String
    let productCount: Int
    let orderCount: Int
    let rating: Double
    let likeCount: Int
    let designLicense: String
    let isVerified: Bool
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, displayName, handle, bio, avatarURL, bannerURL, websiteURL
        case location, materials, processingTime
        case productCount, orderCount, rating, likeCount, designLicense, isVerified, joinedAt
        case shipsInMinDays, shipsInMaxDays
    }

    init(id: String, displayName: String, handle: String, bio: String,
         avatarURL: URL? = nil, bannerURL: URL? = nil, websiteURL: URL? = nil,
         location: String, shipsInDays: ClosedRange<Int>,
         materials: [String], processingTime: String,
         productCount: Int, orderCount: Int, rating: Double,
         likeCount: Int = 0, designLicense: String = "Original",
         isVerified: Bool, joinedAt: Date) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.bio = bio
        self.avatarURL = avatarURL
        self.bannerURL = bannerURL
        self.websiteURL = websiteURL
        self.location = location
        self.shipsInDays = shipsInDays
        self.materials = materials
        self.processingTime = processingTime
        self.productCount = productCount
        self.orderCount = orderCount
        self.rating = rating
        self.likeCount = likeCount
        self.designLicense = designLicense
        self.isVerified = isVerified
        self.joinedAt = joinedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        handle = try c.decode(String.self, forKey: .handle)
        bio = try c.decode(String.self, forKey: .bio)
        if let url = try c.decodeIfPresent(URL.self, forKey: .avatarURL) {
            avatarURL = url
        } else if let urlString = try c.decodeIfPresent(String.self, forKey: .avatarURL) {
            avatarURL = URL(string: urlString)
        } else {
            avatarURL = nil
        }
        if let url = try c.decodeIfPresent(URL.self, forKey: .bannerURL) {
            bannerURL = url
        } else if let urlString = try c.decodeIfPresent(String.self, forKey: .bannerURL) {
            bannerURL = URL(string: urlString)
        } else {
            bannerURL = nil
        }
        if let url = try c.decodeIfPresent(URL.self, forKey: .websiteURL) {
            websiteURL = url
        } else if let urlString = try c.decodeIfPresent(String.self, forKey: .websiteURL) {
            websiteURL = URL(string: urlString)
        } else {
            websiteURL = nil
        }
        location = try c.decode(String.self, forKey: .location)
        materials = try c.decode([String].self, forKey: .materials)
        processingTime = try c.decode(String.self, forKey: .processingTime)
        productCount = try c.decode(Int.self, forKey: .productCount)
        orderCount = try c.decode(Int.self, forKey: .orderCount)
        rating = try c.decode(Double.self, forKey: .rating)
        likeCount = try c.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        designLicense = try c.decodeIfPresent(String.self, forKey: .designLicense) ?? "Original"
        isVerified = try c.decode(Bool.self, forKey: .isVerified)
        if let date = try c.decodeIfPresent(Date.self, forKey: .joinedAt) {
            joinedAt = date
        } else {
            let dateString = try c.decode(String.self, forKey: .joinedAt)
            if let date = ISO8601DateFormatter().date(from: dateString) {
                joinedAt = date
            } else {
                throw DecodingError.dataCorruptedError(forKey: .joinedAt, in: c, debugDescription: "Invalid date format for joinedAt; expected ISO8601")
            }
        }
        let decodedMin = try c.decodeIfPresent(Int.self, forKey: .shipsInMinDays)
        let decodedMax = try c.decodeIfPresent(Int.self, forKey: .shipsInMaxDays)
        let fallbackMin = 0
        let fallbackMax = 0
        let minDays = decodedMin ?? fallbackMin
        let maxDays = decodedMax ?? fallbackMax
        let lower = min(minDays, maxDays)
        let upper = max(minDays, maxDays)
        shipsInDays = lower...upper
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(handle, forKey: .handle)
        try c.encode(bio, forKey: .bio)
        if let url = avatarURL { try c.encode(url.absoluteString, forKey: .avatarURL) }
        if let url = bannerURL { try c.encode(url.absoluteString, forKey: .bannerURL) }
        if let url = websiteURL { try c.encode(url.absoluteString, forKey: .websiteURL) }
        try c.encode(location, forKey: .location)
        try c.encode(materials, forKey: .materials)
        try c.encode(processingTime, forKey: .processingTime)
        try c.encode(productCount, forKey: .productCount)
        try c.encode(orderCount, forKey: .orderCount)
        try c.encode(rating, forKey: .rating)
        try c.encode(likeCount, forKey: .likeCount)
        try c.encode(designLicense, forKey: .designLicense)
        try c.encode(isVerified, forKey: .isVerified)
        let iso = ISO8601DateFormatter()
        try c.encode(iso.string(from: joinedAt), forKey: .joinedAt)
        try c.encode(shipsInDays.lowerBound, forKey: .shipsInMinDays)
        try c.encode(shipsInDays.upperBound, forKey: .shipsInMaxDays)
    }
}

// MARK: - Sample Data

extension SellerProfile {
    static let sample = SellerProfile(
        id: "seller_001",
        displayName: "PrintCraft Studio",
        handle: "@printcraft",
        bio: "Handcrafted 3D-printed home and desk accessories. Every piece is printed fresh to order with premium filament. Based in Austin, TX.",
        avatarURL: nil,
        bannerURL: nil,
        websiteURL: URL(string: "https://printcraft.example.com"),
        location: "Austin, TX",
        shipsInDays: 2...4,
        materials: ["PLA+", "PETG", "Translucent PETG"],
        processingTime: "1–2 business days",
        productCount: 12,
        orderCount: 48,
        rating: 4.9,
        likeCount: 2600,
        designLicense: "Original Designs",
        isVerified: true,
        joinedAt: ISO8601DateFormatter().date(from: "2025-11-01T00:00:00Z")!
    )

    /// Mock lookup by id for use with MockData products.
    static func mockLookup(id: String) -> SellerProfile? {
        [sample, sampleSecond].first { $0.id == id }
    }

    static let sampleSecond = SellerProfile(
        id: "seller_002",
        displayName: "Nozzle Works",
        handle: "@nozzleworks",
        bio: "Precision-printed car and tech accessories. Engineered for a snug fit every time.",
        avatarURL: nil,
        bannerURL: nil,
        websiteURL: nil,
        location: "Denver, CO",
        shipsInDays: 2...5,
        materials: ["PETG", "ABS"],
        processingTime: "2–3 business days",
        productCount: 8,
        orderCount: 23,
        rating: 4.7,
        likeCount: 450,
        designLicense: "CC BY-NC",
        isVerified: false,
        joinedAt: ISO8601DateFormatter().date(from: "2026-01-15T00:00:00Z")!
    )
}
