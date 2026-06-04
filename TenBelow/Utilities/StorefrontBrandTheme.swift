import SwiftUI

/// Default storefront accent palette. Sellers use TenBelow blue until custom banner/theme fields exist.
struct StorefrontBrandTheme {
    let accent: Color
    let accentSecondary: Color
    let bannerGradient: [Color]
    let stripeGradient: [Color]

    /// Matches the seller dashboard hero card default.
    static let defaultBannerColors: [Color] = [
        Color(red: 0.30, green: 0.58, blue: 0.96),
        Color(red: 0.48, green: 0.72, blue: 0.98),
        Color(red: 0.83, green: 0.91, blue: 1.0),
    ]

    static let `default` = StorefrontBrandTheme(
        accent: TBTheme.accent,
        accentSecondary: TBTheme.skyBlue,
        bannerGradient: defaultBannerColors,
        stripeGradient: [
            TBTheme.accent.opacity(0.85),
            TBTheme.skyBlue.opacity(0.65),
            TBTheme.icyBlue.opacity(0.35),
        ]
    )

    static func theme(for sellerId: String) -> StorefrontBrandTheme {
        _ = sellerId
        return .default
    }
}
