import SwiftUI

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    var showsBorder: Bool
    /// When set, draws the same snowfall as title banners behind the frosted material.
    var snowfallFlakeCount: Int?
    var contentPadding: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = 22,
        showsBorder: Bool = true,
        snowfallFlakeCount: Int? = nil,
        contentPadding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.showsBorder = showsBorder
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
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.9),
                                    TBTheme.skyBlue.opacity(0.35),
                                    TBTheme.deepSky.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            }
            .shadow(color: TBTheme.deepSky.opacity(0.08), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
            .shadow(color: .black.opacity(0.06), radius: 24, x: 0, y: 12)
    }
}
