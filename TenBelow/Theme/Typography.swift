//
//  Typography.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Font {
    static let tbLargeTitle  = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let tbTitle       = Font.system(.title2, design: .rounded, weight: .bold)
    static let tbHeadline    = Font.system(.headline, design: .rounded, weight: .semibold)
    static let tbSubheadline = Font.system(.subheadline, design: .rounded, weight: .medium)
    static let tbCaption     = Font.system(.caption, design: .rounded, weight: .medium)
    static let tbPrice       = Font.system(.title3, design: .rounded, weight: .bold)
    static let tbPriceSmall  = Font.system(.subheadline, design: .rounded, weight: .bold)
    static let tbSectionTitle = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let tbCardTitle    = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let tbBody         = Font.system(size: 14, weight: .medium, design: .rounded)
    static let tbBodyStrong   = Font.system(size: 14, weight: .semibold, design: .rounded)
    static let tbMeta         = Font.system(size: 12, weight: .medium, design: .rounded)
    static let tbMicro        = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let tbHeroPrice    = Font.system(size: 30, weight: .bold, design: .rounded)

    // Product typography — SF Rounded + heavy weight reads branded and soft (winter/cloud UI).
    // Avoids Font.custom("AvenirNext-…") when the exact name isn’t bundled → falls back to generic SF Pro.
    static let tbProductTitleXL = Font.system(size: 20, weight: .heavy, design: .rounded)
    static let tbProductTitleMD = Font.system(size: 18, weight: .heavy, design: .rounded)
    static let tbProductTitleSM = Font.system(size: 16, weight: .heavy, design: .rounded)
    static let tbProductPriceLG = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let tbProductPriceMD = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let tbProductPriceSM = Font.system(size: 14, weight: .semibold, design: .rounded)
}

#if canImport(UIKit)
extension UIFont {
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif
