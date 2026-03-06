import SwiftUI

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
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
            )
            .shadow(color: TBTheme.deepSky.opacity(0.08), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
            .shadow(color: .black.opacity(0.06), radius: 24, x: 0, y: 12)
    }
}
