//
//  AppLoadingOverlay.swift
//  TenBelow
//
//  Full-screen splash-style loader for app bootstrap and initial catalog hydration only.
//  For in-flow tasks (sign-in, submit, agreement), use AppOperationOverlay instead.
//

import SwiftUI

struct AppLoadingOverlay: View {
    var title: String = "Loading TenBelow"
    var subtitle: String? = "Pulling in the latest products and pricing."
    @State private var logoOpacity = 0.0
    @State private var logoScale = 0.9
    @State private var contentOffset: CGFloat = 18

    var body: some View {
        ZStack {
            WinterSceneBackground()

            VStack(spacing: 0) {
                Spacer()

                AnimatedLogoView()
                    .frame(height: 248)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .offset(y: contentOffset)
                    .shadow(color: .white.opacity(0.18), radius: 18, y: -2)

                Spacer()

                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky.opacity(0.92))
                        .multilineTextAlignment(.center)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.52))
                            .multilineTextAlignment(.center)
                    }

                    ProgressView()
                        .tint(TBTheme.deepSky)
                        .scaleEffect(0.96)
                        .padding(.top, 4)
                }
                .opacity(logoOpacity)
                .padding(.horizontal, 28)
                .padding(.bottom, 64)
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.42)) {
                logoOpacity = 1.0
                logoScale = 1.0
                contentOffset = 0
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle ?? "")")
    }
}
