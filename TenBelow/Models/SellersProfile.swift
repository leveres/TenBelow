import Foundation

enum SellerVerificationPolicy {
    static let minSuccessfulSales = 50
    static let minPositiveReviews = 30
    static let minAverageRating = 4.0
    static let minActiveDays = 30
}

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
    let totalReviewCount: Int
    let positiveReviewCount: Int
    let rating: Double
    let likeCount: Int
    let pageViewCount: Int
    let designLicense: String
    let isVerified: Bool
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, displayName, handle, bio, avatarURL, bannerURL, websiteURL
        case location, materials, processingTime
        case productCount, orderCount, totalReviewCount, positiveReviewCount, rating, likeCount, pageViewCount, designLicense, isVerified, joinedAt
        case shipsInMinDays, shipsInMaxDays
    }

    init(id: String, displayName: String, handle: String, bio: String,
         avatarURL: URL? = nil, bannerURL: URL? = nil, websiteURL: URL? = nil,
         location: String, shipsInDays: ClosedRange<Int>,
         materials: [String], processingTime: String,
         productCount: Int, orderCount: Int, totalReviewCount: Int = 0, positiveReviewCount: Int = 0, rating: Double,
         likeCount: Int = 0, pageViewCount: Int = 0, designLicense: String = "Original",
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
        self.totalReviewCount = totalReviewCount
        self.positiveReviewCount = positiveReviewCount
        self.rating = rating
        self.likeCount = likeCount
        self.pageViewCount = pageViewCount
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
        totalReviewCount = try c.decodeIfPresent(Int.self, forKey: .totalReviewCount) ?? 0
        positiveReviewCount = try c.decodeIfPresent(Int.self, forKey: .positiveReviewCount) ?? 0
        rating = try c.decode(Double.self, forKey: .rating)
        likeCount = try c.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        pageViewCount = try c.decodeIfPresent(Int.self, forKey: .pageViewCount) ?? 0
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
        try c.encode(totalReviewCount, forKey: .totalReviewCount)
        try c.encode(positiveReviewCount, forKey: .positiveReviewCount)
        try c.encode(rating, forKey: .rating)
        try c.encode(likeCount, forKey: .likeCount)
        try c.encode(pageViewCount, forKey: .pageViewCount)
        try c.encode(designLicense, forKey: .designLicense)
        try c.encode(isVerified, forKey: .isVerified)
        let iso = ISO8601DateFormatter()
        try c.encode(iso.string(from: joinedAt), forKey: .joinedAt)
        try c.encode(shipsInDays.lowerBound, forKey: .shipsInMinDays)
        try c.encode(shipsInDays.upperBound, forKey: .shipsInMaxDays)
    }

    var activeDays: Int {
        let dayCount = Calendar.current.dateComponents([.day], from: joinedAt, to: Date()).day ?? 0
        return max(dayCount, 0)
    }

    var hasEarnedVerificationByPolicy: Bool {
        orderCount >= SellerVerificationPolicy.minSuccessfulSales &&
        positiveReviewCount >= SellerVerificationPolicy.minPositiveReviews &&
        rating >= SellerVerificationPolicy.minAverageRating &&
        activeDays >= SellerVerificationPolicy.minActiveDays
    }

    var isTrustedTesterVerified: Bool {
        SellerVerificationStore.isTrustedTesterVerified(sellerId: id)
    }

    /// Unified source of truth for displaying the verification badge.
    var showsVerifiedBadge: Bool {
        isVerified || hasEarnedVerificationByPolicy || isTrustedTesterVerified
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
        totalReviewCount: 40,
        positiveReviewCount: 38,
        rating: 4.9,
        likeCount: 2600,
        pageViewCount: 18400,
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
        totalReviewCount: 18,
        positiveReviewCount: 14,
        rating: 4.7,
        likeCount: 450,
        pageViewCount: 6100,
        designLicense: "CC BY-NC",
        isVerified: false,
        joinedAt: ISO8601DateFormatter().date(from: "2026-01-15T00:00:00Z")!
    )
}

private enum SellerProfileLocalStore {
    static let storageKey = "sellerLocalProfileData"
}

enum SellerVerificationStore {
    private static let trustedTesterPrefix = "sellerTrustedTesterVerified."

    static func setTrustedTesterVerified(_ isVerified: Bool, sellerId: String) {
        let trimmedSellerID = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSellerID.isEmpty else { return }
        UserDefaults.standard.set(isVerified, forKey: trustedTesterPrefix + trimmedSellerID)
    }

    static func isTrustedTesterVerified(sellerId: String) -> Bool {
        let trimmedSellerID = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSellerID.isEmpty else { return false }
        return UserDefaults.standard.bool(forKey: trustedTesterPrefix + trimmedSellerID)
    }
}

extension SellerProfile {
    static func locallyStoredProfile() -> SellerProfile? {
        guard let data = UserDefaults.standard.data(forKey: SellerProfileLocalStore.storageKey) else {
            return nil
        }

        return try? JSONDecoder().decode(SellerProfile.self, from: data)
    }

    static func previewProfile(sellerId: String, businessName: String) -> SellerProfile {
        let trimmedSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBusinessName = businessName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let stored = locallyStoredProfile(),
           trimmedSellerId.isEmpty || stored.id == trimmedSellerId {
            return stored
        }

        let base = SellerProfile.sample
        let resolvedId = trimmedSellerId.isEmpty ? base.id : trimmedSellerId
        let resolvedDisplayName = trimmedBusinessName.isEmpty ? base.displayName : trimmedBusinessName
        let resolvedHandle = trimmedSellerId.isEmpty ? base.handle : "@\(trimmedSellerId)"

        return SellerProfile(
            id: resolvedId,
            displayName: resolvedDisplayName,
            handle: resolvedHandle,
            bio: base.bio,
            avatarURL: base.avatarURL,
            bannerURL: base.bannerURL,
            websiteURL: base.websiteURL,
            location: base.location,
            shipsInDays: base.shipsInDays,
            materials: base.materials,
            processingTime: base.processingTime,
            productCount: base.productCount,
            orderCount: base.orderCount,
            totalReviewCount: base.totalReviewCount,
            positiveReviewCount: base.positiveReviewCount,
            rating: base.rating,
            likeCount: base.likeCount,
            pageViewCount: base.pageViewCount,
            designLicense: base.designLicense,
            isVerified: base.isVerified,
            joinedAt: base.joinedAt
        )
    }

    func storeLocally() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: SellerProfileLocalStore.storageKey)
    }
}

func resolvedSellerProfile(
    sellerId: String,
    storefrontProducts: [Product],
    remoteProfiles: [SellerProfile] = []
) -> SellerProfile? {
    let trimmedSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSellerId.isEmpty else { return nil }

    let sellerProducts = storefrontProducts.filter { $0.sellerId == trimmedSellerId }
    let baseProfile: SellerProfile?

    if let storedProfile = SellerProfile.locallyStoredProfile(), storedProfile.id == trimmedSellerId {
        baseProfile = storedProfile
    } else if let remoteProfile = remoteProfiles.first(where: { $0.id == trimmedSellerId }) {
        baseProfile = remoteProfile
    } else {
        baseProfile = SellerProfile.mockLookup(id: trimmedSellerId)
    }

    if let baseProfile {
        return baseProfile.applyingStorefrontProducts(sellerProducts)
    }

    guard !sellerProducts.isEmpty else { return nil }

    let inferredName = inferredSellerDisplayName(from: trimmedSellerId)
    let shipLowerBound = sellerProducts.map { $0.shipsInDays.lowerBound }.min() ?? 2
    let shipUpperBound = sellerProducts.map { $0.shipsInDays.upperBound }.max() ?? shipLowerBound
    let materials = Array(Set(sellerProducts.map(\.material))).sorted()
    let totalViews = sellerProducts.reduce(0) { $0 + $1.pageViewCount }
    let totalLikes = sellerProducts.reduce(0) { $0 + $1.favoriteCount }

    return SellerProfile(
        id: trimmedSellerId,
        displayName: inferredName,
        handle: "@\(trimmedSellerId.replacingOccurrences(of: " ", with: "").lowercased())",
        bio: "Independent TenBelow seller creating 3D-printed products.",
        avatarURL: nil,
        bannerURL: nil,
        websiteURL: nil,
        location: "TenBelow",
        shipsInDays: shipLowerBound...shipUpperBound,
        materials: materials.isEmpty ? ["PLA+"] : materials,
        processingTime: "Printed fresh to order",
        productCount: sellerProducts.count,
        orderCount: 0,
        totalReviewCount: 0,
        positiveReviewCount: 0,
        rating: 0,
        likeCount: totalLikes,
        pageViewCount: totalViews,
        designLicense: "Original Designs",
        isVerified: false,
        joinedAt: .now
    )
}

func resolvedSellerProfilesByID(
    storefrontProducts: [Product],
    remoteProfiles: [SellerProfile] = []
) -> [String: SellerProfile] {
    Dictionary(
        uniqueKeysWithValues: Set(storefrontProducts.map(\.sellerId)).compactMap { sellerId in
            guard let profile = resolvedSellerProfile(
                sellerId: sellerId,
                storefrontProducts: storefrontProducts,
                remoteProfiles: remoteProfiles
            ) else {
                return nil
            }
            return (sellerId, profile)
        }
    )
}

private func inferredSellerDisplayName(from sellerId: String) -> String {
    sellerId
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .split(whereSeparator: \.isWhitespace)
        .map { token in
            if token.lowercased() == "seller" {
                return "Seller"
            }
            return token.capitalized
        }
        .joined(separator: " ")
}

private extension SellerProfile {
    func applyingStorefrontProducts(_ products: [Product]) -> SellerProfile {
        guard !products.isEmpty else { return self }

        let shipLowerBound = products.map { $0.shipsInDays.lowerBound }.min() ?? shipsInDays.lowerBound
        let shipUpperBound = products.map { $0.shipsInDays.upperBound }.max() ?? shipsInDays.upperBound
        let materials = Array(Set(products.map(\.material))).sorted()
        let aggregatedViews = products.reduce(0) { $0 + $1.pageViewCount }
        let aggregatedLikes = products.reduce(0) { $0 + $1.favoriteCount }

        return SellerProfile(
            id: id,
            displayName: displayName,
            handle: handle,
            bio: bio,
            avatarURL: avatarURL,
            bannerURL: bannerURL,
            websiteURL: websiteURL,
            location: location,
            shipsInDays: shipLowerBound...shipUpperBound,
            materials: materials.isEmpty ? self.materials : materials,
            processingTime: processingTime,
            productCount: products.count,
            orderCount: orderCount,
            totalReviewCount: totalReviewCount,
            positiveReviewCount: positiveReviewCount,
            rating: rating,
            likeCount: max(likeCount, aggregatedLikes),
            pageViewCount: max(pageViewCount, aggregatedViews),
            designLicense: designLicense,
            isVerified: isVerified,
            joinedAt: joinedAt
        )
    }
}
