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
    static let accent       = Color(red: 0.26, green: 0.56, blue: 0.96)   // #438FF5
    static let subtleGray   = Color(red: 0.94, green: 0.95, blue: 0.97)   // #F0F3F7
    static let icyBlue      = Color(red: 0.30, green: 0.52, blue: 0.90)   // #4D85E6 — frost price tint
    static let frostGlow    = Color(red: 0.55, green: 0.78, blue: 1.0)    // #8CC7FF — subtle glow

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
