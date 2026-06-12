import SwiftUI

enum GlassCardBorderStyle {
    /// Subtle frost edge used across most cards.
    case standard
    /// Stronger blue trim + soft glow for cards that should stand out (e.g. order rows).
    case accent
}

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    var showsBorder: Bool
    var borderStyle: GlassCardBorderStyle
    /// When set, draws the same snowfall as title banners behind the frosted material.
    var snowfallFlakeCount: Int?
    var contentPadding: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = 22,
        showsBorder: Bool = true,
        borderStyle: GlassCardBorderStyle = .standard,
        snowfallFlakeCount: Int? = nil,
        contentPadding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.showsBorder = showsBorder
        self.borderStyle = borderStyle
        self.snowfallFlakeCount = snowfallFlakeCount
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .background {
                ZStack {
                    if let flakeCount = snowfallFlakeCount {
                        SnowfallParticleCanvas(flakeCount: flakeCount, animates: false)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                            .allowsHitTesting(false)
                    }
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(borderGradient, lineWidth: borderLineWidth)
                }
            }
            .shadow(color: TBTheme.deepSky.opacity(borderStyle == .accent ? 0 : glowOpacity), radius: glowRadius, x: 0, y: 1)
            .shadow(color: .black.opacity(borderStyle == .accent ? 0 : 0.12), radius: 12, x: 0, y: 6)
            .shadow(color: .black.opacity(borderStyle == .accent ? 0 : 0.06), radius: 24, x: 0, y: 12)
    }

    private var borderGradient: LinearGradient {
        switch borderStyle {
        case .standard:
            return LinearGradient(
                colors: [
                    .white.opacity(0.9),
                    TBTheme.skyBlue.opacity(0.35),
                    TBTheme.deepSky.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .accent:
            return TBTheme.frostEdge
        }
    }

    private var borderLineWidth: CGFloat {
        borderStyle == .accent ? 1.6 : 1.5
    }

    private var glowOpacity: CGFloat {
        borderStyle == .accent ? 0.13 : 0.08
    }

    private var glowRadius: CGFloat {
        borderStyle == .accent ? 4 : 2
    }
}
