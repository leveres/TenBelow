//
//  Product.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/10/26.
//

import Foundation

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
        previousPriceCents: Int? = nil
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
