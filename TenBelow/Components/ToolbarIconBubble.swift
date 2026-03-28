import SwiftUI

struct ToolbarIconBubble<Content: View>: View {
    /// When false, no stroke or outer shadows (avoids a gray “ring” around the circle on some backgrounds).
    var showsGlassRing: Bool
    let content: Content

    init(showsGlassRing: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsGlassRing = showsGlassRing
        self.content = content()
    }

    var body: some View {
        Group {
            if showsGlassRing {
                bubbleCore
                    .shadow(color: .white.opacity(0.35), radius: 1, y: 1)
                    .shadow(color: TBTheme.deepSky.opacity(0.08), radius: 10, y: 5)
            } else {
                bubbleCore
            }
        }
    }

    private var bubbleCore: some View {
        content
            .frame(width: 42, height: 42)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                if showsGlassRing {
                    Circle()
                        .strokeBorder(.white.opacity(0.72), lineWidth: 0.8)
                }
            }
            .contentShape(Circle())
    }
}

