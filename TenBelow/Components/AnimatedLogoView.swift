//
//  AnimatedLogoView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI

struct AnimatedLogoView: View {
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var glowPulse = false
    @State private var snowflakes: [Snowflake] = (0..<18).map { _ in Snowflake() }

    var body: some View {
        ZStack {
            // Snow particles behind + in front of logo
            SnowCanvas(snowflakes: $snowflakes)

            // Logo with glow + shimmer
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260)
                .shadow(color: TBTheme.frostGlow.opacity(glowPulse ? 0.6 : 0.3), radius: glowPulse ? 20 : 12)
                .overlay(
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.25),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .rotationEffect(.degrees(25))
                    .offset(x: shimmerOffset * 300)
                    .mask(
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                    )
                )
        }
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        // Shimmer sweep
        withAnimation(
            .easeInOut(duration: 2.5)
            .repeatForever(autoreverses: false)
            .delay(0.5)
        ) {
            shimmerOffset = 1.0
        }

        // Glow pulse
        withAnimation(
            .easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true)
        ) {
            glowPulse = true
        }
    }
}

// MARK: - Snow Particle System

struct Snowflake: Identifiable {
    let id = UUID()
    var x: CGFloat = .random(in: 0...1)
    var y: CGFloat = .random(in: -0.2...1.0)
    let size: CGFloat = .random(in: 2...5)
    let opacity: Double = .random(in: 0.3...0.8)
    let speed: CGFloat = .random(in: 0.0008...0.003)
    let drift: CGFloat = .random(in: -0.0005...0.0005)
}

private struct SnowCanvas: View {
    @Binding var snowflakes: [Snowflake]
    @State private var timer: Timer?

    var body: some View {
        Canvas { context, size in
            for flake in snowflakes {
                let point = CGPoint(
                    x: flake.x * size.width,
                    y: flake.y * size.height
                )
                let rect = CGRect(
                    x: point.x - flake.size / 2,
                    y: point.y - flake.size / 2,
                    width: flake.size,
                    height: flake.size
                )
                context.opacity = flake.opacity
                context.fill(
                    Circle().path(in: rect),
                    with: .color(.white)
                )
            }
        }
        .allowsHitTesting(false)
        .onAppear { startSnow() }
        .onDisappear { timer?.invalidate() }
    }

    private func startSnow() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { _ in
            for i in snowflakes.indices {
                snowflakes[i].y += snowflakes[i].speed
                snowflakes[i].x += snowflakes[i].drift

                // Reset when fallen past bottom
                if snowflakes[i].y > 1.1 {
                    snowflakes[i].y = -0.05
                    snowflakes[i].x = .random(in: 0...1)
                }
                // Wrap horizontal drift
                if snowflakes[i].x < 0 { snowflakes[i].x = 1.0 }
                if snowflakes[i].x > 1 { snowflakes[i].x = 0.0 }
            }
        }
    }
}

