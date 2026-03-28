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

    let material: String
    let productionNote: String
    let durabilityNote: String
    let careWarnings: [String]
    let shipsInDays: ClosedRange<Int>

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
        material: String,
        productionNote: String,
        durabilityNote: String,
        careWarnings: [String],
        shipsInDays: ClosedRange<Int>
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
        self.material = material
        self.productionNote = productionNote
        self.durabilityNote = durabilityNote
        self.careWarnings = careWarnings
        self.shipsInDays = shipsInDays
    }
}

extension Product {
    var primaryImageReference: String? {
        imageNames.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func mediaURL(for reference: String?) -> URL? {
        guard let trimmed = reference?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            return nil
        }
        return url
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
