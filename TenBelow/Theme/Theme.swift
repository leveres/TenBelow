//
//  Theme.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

enum TBTheme {

    // MARK: - Brand Colors (sky / cloud)

    static let skyBlue      = Color(red: 0.42, green: 0.69, blue: 0.94)   // #6BB0F0
    static let skyLight     = Color(red: 0.76, green: 0.89, blue: 1.0)    // #C2E3FF
    static let cloudWhite   = Color(red: 0.96, green: 0.98, blue: 1.0)    // #F5FAFF
    static let deepSky      = Color(red: 0.20, green: 0.45, blue: 0.78)   // #3373C7
    /// Navy for labels on light “glass” pills over blue hero banners (reads vs mid-blue text on thin material).
    static let bannerCTAForeground = Color(red: 0.04, green: 0.14, blue: 0.38)
    static let accent       = Color(red: 0.26, green: 0.56, blue: 0.96)   // #438FF5
    static let subtleGray   = Color(red: 0.94, green: 0.95, blue: 0.97)   // #F0F3F7
    static let icyBlue      = Color(red: 0.30, green: 0.52, blue: 0.90)   // #4D85E6 — frost price tint
    static let frostGlow    = Color(red: 0.55, green: 0.78, blue: 1.0)    // #8CC7FF — subtle glow
    /// Top tone of the app-wide frost screen gradient; use for sticky chrome that must blend with it.
    static let frostScreenTop = Color(red: 231 / 255, green: 241 / 255, blue: 255 / 255) // #E7F1FF

    // MARK: - Gradients

    static let heroGradient = LinearGradient(
        colors: [skyLight, skyBlue.opacity(0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let titleGradient = LinearGradient(
        colors: [deepSky, skyBlue],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Product names on light cards — readable first: saturated blues only (no pale “shine” band).
    static let productNameTitleGradient = LinearGradient(
        stops: [
            .init(color: deepSky, location: 0),
            .init(color: accent, location: 0.38),
            .init(color: icyBlue, location: 0.62),
            .init(color: deepSky, location: 1)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let frostTitleGradient = LinearGradient(
        colors: [icyBlue, skyBlue, frostGlow],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        colors: [cloudWhite, skyLight.opacity(0.4)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let dropBannerGradient = LinearGradient(
        colors: [deepSky, skyBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Soft blue trim with a white light-catch — shared frost-edge border for cards on light backgrounds.
    static let frostEdge = LinearGradient(
        colors: [
            skyBlue.opacity(0.50),
            .white.opacity(0.65),
            skyBlue.opacity(0.28),
            deepSky.opacity(0.30)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Frost-edge variant for dark/blue surfaces (e.g. Deal of the Day banner) — white-leaning light catch.
    static let frostEdgeOnDark = LinearGradient(
        colors: [
            .white.opacity(0.55),
            .white.opacity(0.18),
            .white.opacity(0.38)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Spacing

    static let spacingXS:  CGFloat = 4
    static let spacingSM:  CGFloat = 8
    static let spacingMD:  CGFloat = 12
    static let spacingLG:  CGFloat = 16
    static let spacingXL:  CGFloat = 20
    static let spacingXXL: CGFloat = 24

    // MARK: - Corner Radius

    static let radiusSM:  CGFloat = 10
    static let radiusMD:  CGFloat = 14
    static let radiusLG:  CGFloat = 18
    static let radiusXL:  CGFloat = 22
}

// MARK: - Reusable Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(TBTheme.accent)
            .cornerRadius(16)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct PrimaryCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, newValue in
                #if os(iOS)
                if newValue {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                #endif
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [TBTheme.accent, TBTheme.deepSky],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .shadow(color: TBTheme.accent.opacity(0.25), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}

struct SecondaryCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, newValue in
                #if os(iOS)
                if newValue {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                #endif
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(TBTheme.deepSky)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: TBTheme.deepSky.opacity(0.04), radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}

struct GlassPillButtonStyle: ButtonStyle {
    var isFinal: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isFinal ? .white : TBTheme.deepSky)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if isFinal {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [TBTheme.accent, TBTheme.skyBlue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: TBTheme.accent.opacity(0.35), radius: 12, y: 6)
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .strokeBorder(TBTheme.skyBlue.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: TBTheme.skyBlue.opacity(0.12), radius: 8, y: 4)
                    }
                }
            )
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}

struct PremiumGlassPillButtonStyle: ButtonStyle {
    var isEmphasized: Bool = false
    var expandsToFullWidth: Bool = true
    var horizontalPadding: CGFloat = 32
    var verticalPadding: CGFloat = 16
    var fontSize: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(isEmphasized ? .white : TBTheme.deepSky)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: expandsToFullWidth ? .infinity : nil)
            .background {
                ZStack {
                    if isEmphasized {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        TBTheme.accent,
                                        TBTheme.skyBlue,
                                        TBTheme.deepSky
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.22),
                                        .white.opacity(0.08),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .mask(
                                Capsule()
                                    .inset(by: 1.5)
                            )
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.72),
                                        .white.opacity(0.24),
                                        TBTheme.skyLight.opacity(0.18)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.1
                            )
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.36),
                                        TBTheme.skyLight.opacity(0.20),
                                        .white.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.48),
                                        .white.opacity(0.16),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .mask(
                                Capsule()
                                    .inset(by: 1.5)
                            )

                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.86),
                                        .white.opacity(0.28),
                                        TBTheme.skyBlue.opacity(0.14)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    }
                }
                .shadow(
                    color: isEmphasized ? TBTheme.accent.opacity(0.32) : .white.opacity(0.16),
                    radius: isEmphasized ? 14 : 4,
                    y: isEmphasized ? 6 : -1
                )
                .shadow(
                    color: isEmphasized ? TBTheme.deepSky.opacity(0.20) : TBTheme.deepSky.opacity(0.10),
                    radius: isEmphasized ? 16 : 12,
                    y: isEmphasized ? 8 : 6
                )
            }
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct FrostedTextModifier: ViewModifier {
    var edgeOpacity: Double = 0.32
    var shadowOpacity: Double = 0.16

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    content
                        .offset(x: 1, y: 0)
                        .foregroundStyle(TBTheme.deepSky.opacity(0.30 + edgeOpacity))
                    content
                        .offset(x: -1, y: 0)
                        .foregroundStyle(TBTheme.deepSky.opacity(0.30 + edgeOpacity))
                    content
                        .offset(x: 0, y: 1)
                        .foregroundStyle(TBTheme.deepSky.opacity(0.30 + edgeOpacity))
                    content
                        .offset(x: 0, y: -1)
                        .foregroundStyle(TBTheme.deepSky.opacity(0.30 + edgeOpacity))
                    content
                        .offset(x: 1, y: 1)
                        .foregroundStyle(TBTheme.skyBlue.opacity(0.18 + edgeOpacity))
                    content
                        .offset(x: -1, y: 1)
                        .foregroundStyle(TBTheme.skyBlue.opacity(0.18 + edgeOpacity))
                    content
                        .offset(x: 1, y: -1)
                        .foregroundStyle(TBTheme.skyBlue.opacity(0.18 + edgeOpacity))
                    content
                        .offset(x: -1, y: -1)
                        .foregroundStyle(TBTheme.skyBlue.opacity(0.18 + edgeOpacity))
                }
            }
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        .white.opacity(0.92),
                        TBTheme.skyLight.opacity(0.88),
                        TBTheme.frostGlow.opacity(0.82),
                        TBTheme.skyBlue.opacity(0.84)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: .white.opacity(0.16), radius: 0, x: 0, y: -1)
            .shadow(color: TBTheme.deepSky.opacity(shadowOpacity + 0.12), radius: 0.6, x: 0, y: 1)
            .overlay {
                content
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.42),
                                .white.opacity(0.10),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .opacity(0.72)
            }
    }
}

extension View {
    func frostedText(edgeOpacity: Double = 0.32, shadowOpacity: Double = 0.16) -> some View {
        modifier(FrostedTextModifier(edgeOpacity: edgeOpacity, shadowOpacity: shadowOpacity))
    }

    /// Product titles: brand gradient + one crisp edge shadow (no light halos that reduce clarity).
    func tbProductNameTitleStyle() -> some View {
        self
            .foregroundStyle(TBTheme.productNameTitleGradient)
            .shadow(color: TBTheme.deepSky.opacity(0.45), radius: 0, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.10), radius: 0, x: 0, y: 1.5)
    }
}

// MARK: - Frosted screen background

/// App-wide frosted screen background: ice-blue gradient (#E7F1FF → #F7FAFF)
/// with a faint tiled snowflake texture. Decorative only — never intercepts
/// touches and is hidden from accessibility.
struct TBFrostBackground: View {
    private static let iceBottom = Color(red: 247 / 255, green: 250 / 255, blue: 255 / 255) // #F7FAFF

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [TBTheme.frostScreenTop, Self.iceBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            SnowflakeCrystalPattern()
                .opacity(0.08)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Static tiled snowflake texture drawn in a single Canvas pass.
private struct SnowflakeCrystalPattern: View {
    var body: some View {
        Canvas { context, size in
            guard let flake = context.resolveSymbol(id: 0) else { return }
            let tile: CGFloat = 78
            let flakeSize = CGSize(width: 22, height: 22)
            var row = 0
            var y: CGFloat = tile / 2
            while y < size.height + tile {
                // Stagger alternating rows for a natural crystal scatter.
                let xOffset: CGFloat = row.isMultiple(of: 2) ? tile / 2 : 0
                var x: CGFloat = xOffset
                while x < size.width + tile {
                    var flakeContext = context
                    // Slight per-tile rotation keeps the pattern from feeling like a grid.
                    let rotation = Angle.degrees(Double((row + Int(x / tile)) % 4) * 22.5)
                    flakeContext.translateBy(x: x, y: y)
                    flakeContext.rotate(by: rotation)
                    flakeContext.draw(
                        flake,
                        in: CGRect(
                            x: -flakeSize.width / 2,
                            y: -flakeSize.height / 2,
                            width: flakeSize.width,
                            height: flakeSize.height
                        )
                    )
                    x += tile
                }
                y += tile
                row += 1
            }
        } symbols: {
            Image(systemName: "snowflake")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(TBTheme.deepSky)
                .tag(0)
        }
    }
}
