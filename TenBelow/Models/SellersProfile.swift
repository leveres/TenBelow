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
    /// Raw value from the API (often `/media/...`). Resolved lazily so host-relative paths work once `TENBELOW_BACKEND_BASE_URL` is configured.
    let avatarMediaReference: String?
    /// Same resolution rules as `avatarMediaReference`.
    let bannerMediaReference: String?
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
    /// When true, buyers see a control on the public storefront to submit a custom-order request.
    let acceptsCustomOrders: Bool
    /// Optional URL (e.g. guidelines, portfolio, or intake form) shown in the custom-order sheet.
    let customOrderInfoURL: URL?
    let joinedAt: Date

    var avatarURL: URL? {
        Self.resolveMediaReference(avatarMediaReference)
    }

    var bannerURL: URL? {
        Self.resolveMediaReference(bannerMediaReference)
    }

    private static func resolveMediaReference(_ raw: String?) -> URL? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return Product.previewMediaURL(for: trimmed)
    }

    private static func mergedOptionalMediaRef(_ primary: String?, _ fallback: String?) -> String? {
        let p = primary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !p.isEmpty { return primary }
        let f = fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return f.isEmpty ? nil : fallback
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, handle, bio, avatarURL, bannerURL, websiteURL
        case location, materials, processingTime
        case productCount, orderCount, totalReviewCount, positiveReviewCount, rating, likeCount, pageViewCount, designLicense, isVerified, joinedAt
        case shipsInMinDays, shipsInMaxDays
        case acceptsCustomOrders, customOrderInfoURL
    }

    init(id: String, displayName: String, handle: String, bio: String,
         avatarMediaReference: String? = nil, bannerMediaReference: String? = nil, websiteURL: URL? = nil,
         location: String, shipsInDays: ClosedRange<Int>,
         materials: [String], processingTime: String,
         productCount: Int, orderCount: Int, totalReviewCount: Int = 0, positiveReviewCount: Int = 0, rating: Double,
         likeCount: Int = 0, pageViewCount: Int = 0, designLicense: String = "Original",
         isVerified: Bool, acceptsCustomOrders: Bool = false, customOrderInfoURL: URL? = nil, joinedAt: Date) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.bio = bio
        self.avatarMediaReference = avatarMediaReference
        self.bannerMediaReference = bannerMediaReference
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
        self.acceptsCustomOrders = acceptsCustomOrders
        self.customOrderInfoURL = customOrderInfoURL
        self.joinedAt = joinedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        handle = try c.decode(String.self, forKey: .handle)
        bio = try c.decode(String.self, forKey: .bio)
        // Keep raw strings; `avatarURL` / `bannerURL` resolve via `Product.previewMediaURL` on each read
        // so the same build works if the API base URL becomes available later.
        if let raw = try c.decodeIfPresent(String.self, forKey: .avatarURL) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            avatarMediaReference = trimmed.isEmpty ? nil : trimmed
        } else {
            avatarMediaReference = nil
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .bannerURL) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            bannerMediaReference = trimmed.isEmpty ? nil : trimmed
        } else {
            bannerMediaReference = nil
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .websiteURL) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                websiteURL = nil
            } else if let absolute = URL(string: trimmed), absolute.scheme != nil {
                websiteURL = absolute
            } else {
                websiteURL = Product.previewMediaURL(for: trimmed)
            }
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
        acceptsCustomOrders = try c.decodeIfPresent(Bool.self, forKey: .acceptsCustomOrders) ?? false
        if let raw = try c.decodeIfPresent(String.self, forKey: .customOrderInfoURL) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                customOrderInfoURL = nil
            } else {
                customOrderInfoURL = URL(string: trimmed) ?? Product.previewMediaURL(for: trimmed)
            }
        } else {
            customOrderInfoURL = nil
        }
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
        if let ref = avatarMediaReference, !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try c.encode(ref.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .avatarURL)
        }
        if let ref = bannerMediaReference, !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try c.encode(ref.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .bannerURL)
        }
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
        try c.encode(acceptsCustomOrders, forKey: .acceptsCustomOrders)
        if let url = customOrderInfoURL { try c.encode(url.absoluteString, forKey: .customOrderInfoURL) }
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
        avatarMediaReference: nil,
        bannerMediaReference: nil,
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
        acceptsCustomOrders: true,
        customOrderInfoURL: nil,
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
        avatarMediaReference: nil,
        bannerMediaReference: nil,
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
        acceptsCustomOrders: false,
        customOrderInfoURL: nil,
        joinedAt: ISO8601DateFormatter().date(from: "2026-01-15T00:00:00Z")!
    )
}

private enum SellerProfileLocalStore {
    static let storageKey = "sellerLocalProfileData"
}

private enum BuyerEngagementSnapshotStore {
    static let storageKey = "buyerEngagementStore.snapshots"
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
    static func starterProfile(sellerId: String, businessName: String) -> SellerProfile {
        let trimmedSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBusinessName = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayName = trimmedBusinessName.isEmpty
            ? inferredSellerDisplayName(from: trimmedSellerId)
            : trimmedBusinessName

        return SellerProfile(
            id: trimmedSellerId,
            displayName: resolvedDisplayName,
            handle: "@\(trimmedSellerId)",
            bio: "",
            avatarMediaReference: nil,
            bannerMediaReference: nil,
            websiteURL: nil,
            location: "",
            shipsInDays: 3...7,
            materials: [],
            processingTime: "Made to order",
            productCount: 0,
            orderCount: 0,
            totalReviewCount: 0,
            positiveReviewCount: 0,
            rating: 0,
            likeCount: 0,
            pageViewCount: 0,
            designLicense: "Original",
            isVerified: false,
            acceptsCustomOrders: false,
            customOrderInfoURL: nil,
            joinedAt: .now
        )
    }

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
            avatarMediaReference: base.avatarMediaReference,
            bannerMediaReference: base.bannerMediaReference,
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
            acceptsCustomOrders: base.acceptsCustomOrders,
            customOrderInfoURL: base.customOrderInfoURL,
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
    let storedProfile = SellerProfile.locallyStoredProfile().flatMap { profile in
        profile.id == trimmedSellerId ? profile : nil
    }
    let remoteProfile = remoteProfiles.first(where: { $0.id == trimmedSellerId })

    if let remoteProfile {
        baseProfile = remoteProfile.mergingFallback(storedProfile)
    } else if let storedProfile {
        baseProfile = storedProfile
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
    let totalFollowers = persistedFollowerCount(forSellerId: trimmedSellerId)

    return SellerProfile(
        id: trimmedSellerId,
        displayName: inferredName,
        handle: "@\(trimmedSellerId.replacingOccurrences(of: " ", with: "").lowercased())",
        bio: "Independent TenBelow seller creating 3D-printed products.",
        avatarMediaReference: nil,
        bannerMediaReference: nil,
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
        likeCount: totalLikes + totalFollowers,
        pageViewCount: totalViews,
        designLicense: "Original Designs",
        isVerified: false,
        acceptsCustomOrders: false,
        customOrderInfoURL: nil,
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

extension SellerProfile {
    /// Label for product cards when a resolved profile isn’t available (e.g. catalog key mismatch).
    static func fallbackDisplayName(forSellerId sellerId: String) -> String {
        let trimmed = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Seller" }
        return inferredSellerDisplayName(from: trimmed)
    }
}

extension SellerProfile {
    func mergingFallback(_ fallback: SellerProfile?) -> SellerProfile {
        guard let fallback else { return self }

        let resolvedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallback.displayName
            : displayName
        let resolvedHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallback.handle
            : handle
        let resolvedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallback.bio
            : bio
        let resolvedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallback.location
            : location
        let resolvedProcessingTime = processingTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallback.processingTime
            : processingTime

        return SellerProfile(
            id: id,
            displayName: resolvedDisplayName,
            handle: resolvedHandle,
            bio: resolvedBio,
            avatarMediaReference: Self.mergedOptionalMediaRef(avatarMediaReference, fallback.avatarMediaReference),
            bannerMediaReference: Self.mergedOptionalMediaRef(bannerMediaReference, fallback.bannerMediaReference),
            websiteURL: websiteURL ?? fallback.websiteURL,
            location: resolvedLocation,
            shipsInDays: shipsInDays,
            materials: materials.isEmpty ? fallback.materials : materials,
            processingTime: resolvedProcessingTime,
            productCount: max(productCount, fallback.productCount),
            orderCount: max(orderCount, fallback.orderCount),
            totalReviewCount: max(totalReviewCount, fallback.totalReviewCount),
            positiveReviewCount: max(positiveReviewCount, fallback.positiveReviewCount),
            rating: max(rating, fallback.rating),
            likeCount: max(likeCount, fallback.likeCount),
            pageViewCount: max(pageViewCount, fallback.pageViewCount),
            designLicense: designLicense.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback.designLicense : designLicense,
            isVerified: isVerified || fallback.isVerified,
            acceptsCustomOrders: acceptsCustomOrders || fallback.acceptsCustomOrders,
            customOrderInfoURL: customOrderInfoURL ?? fallback.customOrderInfoURL,
            joinedAt: joinedAt
        )
    }

    func applyingStorefrontProducts(_ products: [Product]) -> SellerProfile {
        guard !products.isEmpty else { return self }

        let shipLowerBound = products.map { $0.shipsInDays.lowerBound }.min() ?? shipsInDays.lowerBound
        let shipUpperBound = products.map { $0.shipsInDays.upperBound }.max() ?? shipsInDays.upperBound
        let materials = Array(Set(products.map(\.material))).sorted()
        let aggregatedViews = products.reduce(0) { $0 + $1.pageViewCount }
        let aggregatedLikes = products.reduce(0) { $0 + $1.favoriteCount }
        let aggregatedFollowers = persistedFollowerCount(forSellerId: id)

        return SellerProfile(
            id: id,
            displayName: displayName,
            handle: handle,
            bio: bio,
            avatarMediaReference: avatarMediaReference,
            bannerMediaReference: bannerMediaReference,
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
            likeCount: max(likeCount, aggregatedLikes + aggregatedFollowers),
            pageViewCount: max(pageViewCount, aggregatedViews),
            designLicense: designLicense,
            isVerified: isVerified,
            acceptsCustomOrders: acceptsCustomOrders,
            customOrderInfoURL: customOrderInfoURL,
            joinedAt: joinedAt
        )
    }
}

private func persistedFollowerCount(forSellerId sellerId: String) -> Int {
    let trimmedSellerId = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSellerId.isEmpty else { return 0 }

    let snapshots: [String: BuyerEngagementSnapshot] = LocalCodableStore.load(
        key: BuyerEngagementSnapshotStore.storageKey,
        default: [:]
    )

    return snapshots.values.reduce(0) { count, snapshot in
        count + (snapshot.followedSellerIDs.contains(trimmedSellerId) ? 1 : 0)
    }
}
