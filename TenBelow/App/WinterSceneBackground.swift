import SwiftUI

struct WinterSceneBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.97, blue: 1.0),
                    Color(red: 0.80, green: 0.90, blue: 1.0),
                    Color(red: 0.72, green: 0.87, blue: 0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.white.opacity(0.42))
                .frame(width: 320, height: 320)
                .blur(radius: 42)
                .offset(x: -110, y: -260)

            Circle()
                .fill(TBTheme.frostGlow.opacity(0.26))
                .frame(width: 260, height: 260)
                .blur(radius: 48)
                .offset(x: 130, y: 260)

            WinterSnowfallOverlay()
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}

private struct WinterSnowfallOverlay: View {
    var body: some View {
        let flakes = (0..<120).map(WinterSnowParticle.init(seed:))

        GeometryReader { _ in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                let time = CGFloat(timeline.date.timeIntervalSinceReferenceDate)

                Canvas { context, size in
                    for flake in flakes {
                        let yRange = size.height + (flake.size * 2.0)
                        let y = (time * flake.speed + flake.phase * yRange)
                            .truncatingRemainder(dividingBy: yRange) - flake.size

                        let xBase = flake.x * size.width
                        let xDrift = sin((time * flake.driftFrequency) + flake.phase * .pi * 2.0) * flake.driftAmount
                        let x = min(max(xBase + xDrift, -flake.size), size.width + flake.size)

                        let rect = CGRect(x: x, y: y, width: flake.size, height: flake.size)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(.white.opacity(flake.opacity))
                        )
                    }
                }
            }
        }
        .opacity(0.82)
    }
}

private struct WinterSnowParticle {
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

        let n1 = normalized(11)
        let n2 = normalized(29)
        let n3 = normalized(47)
        let n4 = normalized(71)
        let n5 = normalized(89)
        let n6 = normalized(131)
        let n7 = normalized(173)

        x = n1
        size = 2.8 + (n2 * 5.2)
        opacity = 0.34 + Double(n3) * 0.36
        speed = 12.0 + (n4 * 20.0)
        phase = n5
        driftAmount = 5.0 + (n6 * 12.0)
        driftFrequency = 0.25 + (n7 * 0.45)
    }
}

