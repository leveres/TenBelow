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
}

#if canImport(UIKit)
extension UIFont {
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif
