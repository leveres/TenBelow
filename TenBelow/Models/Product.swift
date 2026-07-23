//
//  Product.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/10/26.
//

import Foundation

enum ProductRightsOwnershipOption: String, CaseIterable, Identifiable, Codable {
    case createdMyself = "I created this product myself"
    case ownCommercialRights = "I own the commercial rights to this product"
    case purchasedCommercialLicense = "I purchased a commercial license to sell this product"
    case writtenPermission = "I have written permission from the creator or rights holder"
    case other = "Other"

    var id: String { rawValue }

    var requiresManualReview: Bool {
        switch self {
        case .createdMyself, .ownCommercialRights:
            return false
        case .purchasedCommercialLicense, .writtenPermission, .other:
            return true
        }
    }
}

enum ProductRightsReferenceFlag: String, CaseIterable, Identifiable, Codable {
    case brandLogos = "Brand logos"
    case sportsTeams = "Sports teams"
    case moviesOrTelevisionCharacters = "Movies or television characters"
    case videoGameCharacters = "Video game characters"
    case celebrityLikenesses = "Celebrity likenesses"
    case trademarkedNames = "Trademarked names"
    case noneOfTheAbove = "None of the above"

    var id: String { rawValue }
}

enum ProductRightsReview {
    static let manualReviewReason = "Potential brand, trademark, character, or likeness reference"

    static func requiresManualReview(ownershipType: String?, referenceFlags: [String]) -> Bool {
        if referenceFlags.contains(where: { $0 != ProductRightsReferenceFlag.noneOfTheAbove.rawValue }) {
            return true
        }

        guard let ownershipType,
              let ownershipOption = ProductRightsOwnershipOption(rawValue: ownershipType)
        else {
            return false
        }

        return ownershipOption.requiresManualReview
    }

    static func reviewReason(referenceFlags: [String]) -> String? {
        referenceFlags.contains(where: { $0 != ProductRightsReferenceFlag.noneOfTheAbove.rawValue })
            ? manualReviewReason
            : nil
    }
}

struct Product: Identifiable, Hashable {
    let id: String
    let sellerId: String
    let name: String
    let priceCents: Int
    let category: Category

    let imageNames: [String]
    let demoVideoURL: URL?
    /// Post-purchase clip for buyer Order Details ("Production Preview").
    /// Kept separate from public product gallery and promo media.
    let productionPreviewURL: URL?
    let pageViewCount: Int
    let favoriteCount: Int
    let averageRating: Double
    let reviewCount: Int

    let material: String
    let productionNote: String
    let durabilityNote: String
    let careWarnings: [String]
    let shipsInDays: ClosedRange<Int>
    let createdAt: Date
    let previousPriceCents: Int?
    let rightsOwnershipType: String?
    let rightsReferenceFlags: [String]
    let rightsCertificationAccepted: Bool
    let rightsCertificationAcceptedAt: Date?
    let requiresManualReview: Bool
    let reviewReason: String?

    init(
        id: String,
        sellerId: String,
        name: String,
        priceCents: Int,
        category: Category,
        imageNames: [String],
        demoVideoURL: URL?,
        productionPreviewURL: URL? = nil,
        pageViewCount: Int,
        favoriteCount: Int,
        averageRating: Double = 0,
        reviewCount: Int = 0,
        material: String,
        productionNote: String,
        durabilityNote: String,
        careWarnings: [String],
        shipsInDays: ClosedRange<Int>,
        createdAt: Date = .now,
        previousPriceCents: Int? = nil,
        rightsOwnershipType: String? = nil,
        rightsReferenceFlags: [String] = [],
        rightsCertificationAccepted: Bool = false,
        rightsCertificationAcceptedAt: Date? = nil,
        requiresManualReview: Bool = false,
        reviewReason: String? = nil
    ) {
        self.id = id
        self.sellerId = sellerId
        self.name = name
        self.priceCents = priceCents
        self.category = category
        self.imageNames = imageNames
        self.demoVideoURL = demoVideoURL
        self.productionPreviewURL = productionPreviewURL
        self.pageViewCount = pageViewCount
        self.favoriteCount = favoriteCount
        self.averageRating = averageRating
        self.reviewCount = reviewCount
        self.material = material
        self.productionNote = productionNote
        self.durabilityNote = durabilityNote
        self.careWarnings = careWarnings
        self.shipsInDays = shipsInDays
        self.createdAt = createdAt
        self.previousPriceCents = previousPriceCents
        self.rightsOwnershipType = rightsOwnershipType
        self.rightsReferenceFlags = rightsReferenceFlags
        self.rightsCertificationAccepted = rightsCertificationAccepted
        self.rightsCertificationAcceptedAt = rightsCertificationAcceptedAt
        self.requiresManualReview = requiresManualReview
        self.reviewReason = reviewReason
    }
}

extension Product {
    var isRecentlyAdded: Bool {
        Date.now.timeIntervalSince(createdAt) <= 60 * 60 * 24 * 7
    }

    var hasPriceDrop: Bool {
        guard let previousPriceCents else { return false }
        return previousPriceCents > priceCents
    }

    var hasCreatorClip: Bool {
        demoVideoURL != nil
    }

    var hasMakerVideo: Bool {
        productionPreviewURL != nil
    }

    var primaryImageReference: String? {
        imageNames.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func mediaURL(for reference: String?) -> URL? {
        resolvedHTTPMediaURL(for: reference, allowFileURLs: false)
    }

    /// Same references as `imageNames` / `imageURLStrings`, but includes local `file://` URLs so previews can load before upload.
    static func previewMediaURL(for reference: String?) -> URL? {
        resolvedHTTPMediaURL(for: reference, allowFileURLs: true)
    }

    /// Builds a loadable URL for catalog image references: absolute http(s)/file, or host-relative `/media/...` against `AppConstants.backendBaseURL`.
    /// Rewrites `localhost` / `127.0.0.1` to the configured API host when they differ (common when the API base uses a LAN IP but stored URLs still say localhost).
    private static func resolvedHTTPMediaURL(for reference: String?, allowFileURLs: Bool) -> URL? {
        let trimmed = reference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if ["http", "https"].contains(scheme) {
                if let rewrittenCDN = rewriteStaleCDNMediaURLIfNeeded(url) {
                    return rewrittenCDN
                }
                return rewriteLocalhostMediaURLIfNeeded(url)
            }
            if allowFileURLs && scheme == "file" {
                return url
            }
        }

        if trimmed.hasPrefix("/"), let base = AppConstants.backendBaseURL,
           let absolute = URL(string: trimmed, relativeTo: base)?.absoluteURL {
            return rewriteLocalhostMediaURLIfNeeded(absolute)
        }

        return nil
    }

    private static func rewriteStaleCDNMediaURLIfNeeded(_ url: URL) -> URL? {
        guard let configured = AppConstants.backendBaseURL,
              let configuredHost = configured.host?.lowercased(),
              !["localhost", "127.0.0.1"].contains(configuredHost),
              let host = url.host?.lowercased(),
              host.contains("r2.dev") || host.contains("cloudflarestorage.com"),
              url.path.contains("/profile/")
        else {
            return nil
        }

        let pathKey = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !pathKey.isEmpty,
              let absolute = URL(string: "/media/\(pathKey)", relativeTo: configured)?.absoluteURL
        else {
            return nil
        }
        return absolute
    }

    private static func rewriteLocalhostMediaURLIfNeeded(_ url: URL) -> URL {
        guard let configured = AppConstants.backendBaseURL,
              let configuredHost = configured.host?.lowercased(),
              let urlHost = url.host?.lowercased(),
              ["localhost", "127.0.0.1"].contains(urlHost),
              configuredHost != urlHost
        else {
            return url
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = configured.scheme
        components.host = configured.host
        components.port = configured.port
        return components.url ?? url
    }
}

#if canImport(UIKit)
import UIKit

extension Product {
    /// First entry in `imageNames` that exists in the asset catalog; otherwise a bundled app image.
    func resolvedPrimaryAssetImageName(
        bundledFallbacks: [String] = ["products_image", "filament_image", "printer_image"]
    ) -> String? {
        for name in imageNames where !name.isEmpty {
            if UIImage(named: name) != nil {
                return name
            }
        }
        for name in bundledFallbacks where UIImage(named: name) != nil {
            return name
        }
        return nil
    }
}
#endif
