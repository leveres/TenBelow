import SwiftUI

// MARK: - Shared particle canvas (titles, cards, hero banners)

/// Same snowfall system as weekly-drop title art; use behind glass or on colored card backgrounds.
struct SnowfallParticleCanvas: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var flakeCount: Int = 24
    var animates: Bool = true

    var body: some View {
        let effectiveAnimates = animates && !reduceMotion
        let effectiveFlakeCount = reduceMotion ? 0 : min(max(flakeCount, 0), 32)
        let flakes = (0..<effectiveFlakeCount).map(TitleSnowParticle.init(seed:))

        Group {
            if effectiveAnimates {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: false)) { timeline in
                    snowCanvas(flakes: flakes, time: CGFloat(timeline.date.timeIntervalSinceReferenceDate))
                }
            } else {
                snowCanvas(flakes: flakes, time: 0)
            }
        }
    }

    private func snowCanvas(flakes: [TitleSnowParticle], time: CGFloat) -> some View {
        Canvas { context, size in
            for flake in flakes {
                let travel = size.height + (flake.size * 2.0)
                let y = (time * flake.speed + flake.phase * travel)
                    .truncatingRemainder(dividingBy: travel) - flake.size

                let baseX = flake.x * size.width
                let drift = sin((time * flake.driftFrequency) + flake.phase * .pi * 2.0) * flake.driftAmount
                let x = min(max(baseX + drift, -flake.size), size.width + flake.size)

                let rect = CGRect(x: x, y: y, width: flake.size, height: flake.size)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(.white.opacity(min(flake.opacity + 0.28, 1.0)))
                )
            }
        }
    }
}

struct SnowfallTitleContainer<Content: View>: View {
    var cornerRadius: CGFloat = 28
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 14
    var flakeCount: Int = 88
    var effectHorizontalInset: CGFloat = 24
    var effectVerticalInset: CGFloat = 20
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                SnowfallParticleCanvas(flakeCount: flakeCount)
                    .padding(.horizontal, -effectHorizontalInset)
                    .padding(.vertical, -effectVerticalInset)
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .padding(.horizontal, -effectHorizontalInset)
                            .padding(.vertical, -effectVerticalInset)
                    )
                    .allowsHitTesting(false)
            }
        // Allow the container to grow horizontally with its parent (e.g. full-width Settings / Shop headers)
        // while still hugging vertical height to the artwork.
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TitleSnowParticle {
    let x: CGFloat
    let size: CGFloat
    let opacity: Double
    let speed: CGFloat
    let phase: CGFloat
    let driftAmount: CGFloat
    let driftFrequency: CGFloat

    nonisolated init(seed: Int) {
        func normalized(_ offset: Int) -> CGFloat {
            let raw = (seed &* 73_856_093 &+ offset &* 19_349_663) & 0xFFFF
            return CGFloat(raw) / CGFloat(0xFFFF)
        }

        let n1 = normalized(5)
        let n2 = normalized(17)
        let n3 = normalized(41)
        let n4 = normalized(63)
        let n5 = normalized(87)
        let n6 = normalized(109)
        let n7 = normalized(141)
        x = n1
        // Small, bright flakes read as snow against soft app backgrounds.
        size = 1.9 + (n2 * 3.5)
        opacity = 0.46 + Double(n3) * 0.42
        speed = 4.0 + (n4 * 6.8)
        phase = n5
        driftAmount = 6.0 + (n6 * 10.0)
        driftFrequency = 0.18 + (n7 * 0.22)
    }
}

#Preview("SnowfallTitleContainer") {
    VStack(spacing: 16) {
        SnowfallTitleContainer(cornerRadius: 24, horizontalPadding: 16, verticalPadding: 12, flakeCount: 24, effectHorizontalInset: 20, effectVerticalInset: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Weekly Drop")
                    .font(.largeTitle.bold())
                Text("Limited edition release")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.blue.opacity(0.2))
        )

        SnowfallTitleContainer(flakeCount: 16) {
            HStack {
                Image(systemName: "snow")
                Text("Snowy Header")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.gray.opacity(0.15))
        )
    }
    .padding()
}
