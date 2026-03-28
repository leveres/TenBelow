//
//  OnboardingPage.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/17/26.
//

import SwiftUI

struct OnboardingPage: View {
    let imageName: String
    let symbolName: String
    let title: String
    let subtitle: String
    var isActive: Bool = false

    private var isSellerArtwork: Bool {
        imageName.hasPrefix("seller_")
    }

    private var topSpacerHeight: CGFloat {
        isSellerArtwork ? 8 : 20
    }

    private var heroMaxHeight: CGFloat {
        if isSellerArtwork {
            return title.count > 22 ? 385 : 410
        }
        return title.count > 22 ? 350 : 380
    }

    private var titleFontSize: CGFloat {
        title.count > 22 ? 29 : 32
    }

    private var textHorizontalPadding: CGFloat {
        title.count > 22 ? 34 : 30
    }

    private var imageHorizontalPadding: CGFloat {
        isSellerArtwork ? 6 : 16
    }

    private var imageScale: CGFloat {
        isSellerArtwork && isActive ? 1.06 : (isSellerArtwork ? 1.03 : 1.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: topSpacerHeight)

            // Hero image — lays on view, no container or borders
            Group {
                if !imageName.isEmpty {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: heroMaxHeight)
                        // Crop a thin artifact on the leading edge of the generated onboarding images.
                        .mask(alignment: .center) {
                            Rectangle()
                                .offset(x: 8)
                        }
                        .shadow(color: .white.opacity(0.35), radius: 14, y: 2)
                        .shadow(color: TBTheme.skyBlue.opacity(0.10), radius: 20, y: 10)
                } else {
                    Image(systemName: symbolName)
                        .font(.system(size: 64, weight: .ultraLight))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [TBTheme.deepSky.opacity(0.6), TBTheme.skyBlue.opacity(0.4)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 200)
                }
            }
            .padding(.horizontal, imageHorizontalPadding)
            .scaleEffect(isActive ? imageScale : imageScale * 0.96)
            .opacity(isActive ? 1.0 : 0.9)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: isActive)

            Spacer().frame(height: isSellerArtwork ? 10 : 18)

            // Text — no borders, clean
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [TBTheme.deepSky, TBTheme.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .white.opacity(0.18), radius: 0, x: 0, y: -1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)

                Text(subtitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, textHorizontalPadding)
            .padding(.top, 2)

            Spacer()
        }
    }
}

#Preview {
    ZStack {
        TBTheme.cloudWhite.ignoresSafeArea()
        OnboardingPage(
            imageName: "filament_image",
            symbolName: "cube.fill",
            title: "Fresh Ideas Start Here",
            subtitle: "High-quality filament. Clean prints. Designed to last.",
            isActive: true
        )
    }
}
