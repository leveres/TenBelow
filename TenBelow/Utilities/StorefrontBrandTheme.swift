import SwiftUI

/// Deterministic accent palette per seller so storefronts feel distinct without server-side theme fields.
struct StorefrontBrandTheme {
    let accent: Color
    let accentSecondary: Color
    let bannerGradient: [Color]
    let stripeGradient: [Color]

    static func theme(for sellerId: String) -> StorefrontBrandTheme {
        let hash = stableHash(sellerId)
        let hue = Double(hash % 360) / 360.0
        let accent = Color(hue: hue, saturation: 0.52, brightness: 0.78)
        let accentSecondary = Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.38, brightness: 0.92)
        let deep = Color(hue: hue, saturation: 0.55, brightness: 0.42)

        return StorefrontBrandTheme(
            accent: accent,
            accentSecondary: accentSecondary,
            bannerGradient: [
                deep.opacity(0.92),
                accent.opacity(0.88),
                accentSecondary.opacity(0.95),
                Color(red: 0.96, green: 0.98, blue: 1.0),
            ],
            stripeGradient: [
                accent.opacity(0.85),
                accentSecondary.opacity(0.65),
                TBTheme.icyBlue.opacity(0.35),
            ]
        )
    }

    private static func stableHash(_ value: String) -> Int {
        value.unicodeScalars.reduce(5381) { partial, scalar in
            ((partial << 5) &+ partial) &+ Int(scalar.value)
        } & 0x7fffffff
    }
}
