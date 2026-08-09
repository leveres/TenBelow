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
    static let tbSectionTitle = Font.system(.headline, design: .rounded, weight: .semibold)
    static let tbCardTitle    = Font.system(.title3, design: .rounded, weight: .semibold)
    static let tbBody         = Font.system(.subheadline, design: .rounded, weight: .medium)
    static let tbBodyStrong   = Font.system(.subheadline, design: .rounded, weight: .semibold)
    static let tbMeta         = Font.system(.caption, design: .rounded, weight: .medium)
    static let tbMicro        = Font.system(.caption2, design: .rounded, weight: .semibold)
    static let tbHeroPrice    = Font.system(.title, design: .rounded, weight: .bold)

    // Product typography — SF Rounded + heavy weight reads branded and soft (winter/cloud UI).
    // Avoids Font.custom("AvenirNext-…") when the exact name isn’t bundled → falls back to generic SF Pro.
    static let tbProductTitleXL = Font.system(.title3, design: .rounded, weight: .heavy)
    static let tbProductTitleMD = Font.system(.headline, design: .rounded, weight: .heavy)
    static let tbProductTitleSM = Font.system(.callout, design: .rounded, weight: .heavy)
    static let tbProductPriceLG = Font.system(.headline, design: .rounded, weight: .semibold)
    static let tbProductPriceMD = Font.system(.callout, design: .rounded, weight: .semibold)
    static let tbProductPriceSM = Font.system(.footnote, design: .rounded, weight: .semibold)
}

#if canImport(UIKit)
extension UIFont {
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif
