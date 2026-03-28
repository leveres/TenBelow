//
//  SplashView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import Combine

struct SplashView: View {
    var onFinish: (() -> Void)? = nil
    @State private var logoOpacity = 0.0
    @State private var logoScale = 0.85
    @State private var contentOffset: CGFloat = 16

    var body: some View {
        ZStack {
            WinterSceneBackground()

            VStack(spacing: 0) {
                Spacer()

                AnimatedLogoView()
                    .frame(height: 260)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .offset(y: contentOffset)

                Spacer()

                VStack(spacing: 8) {
                    Text("Everything $10 & under")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky.opacity(0.86))

                    Text("Fresh 3D printed finds, ready to explore.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.48))
                }
                .opacity(logoOpacity)
                .padding(.bottom, 64)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                logoOpacity = 1.0
                logoScale = 1.0
                contentOffset = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) {
                onFinish?()
            }
        }
    }
}

#Preview {
    SplashView()
        .environmentObject(CartStore())
}
