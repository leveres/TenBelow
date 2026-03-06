//
//  SplashView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI
import Combine

struct SplashView: View {
    @State private var isActive = false
    @State private var logoOpacity = 0.0
    @State private var logoScale = 0.85

    var body: some View {
        if isActive {
            AppRootView()
        } else {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 20) {
                    AnimatedLogoView()
                        .frame(height: 220)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)

                    Text("Everything $10 & under")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(TBTheme.frostGlow)
                        .opacity(logoOpacity)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    logoOpacity = 1.0
                    logoScale = 1.0
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isActive = true
                    }
                }
            }
        }
    }
}

#Preview {
    SplashView()
        .environmentObject(CartStore())
}
