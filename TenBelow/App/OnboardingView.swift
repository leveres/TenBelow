//
//  OnboardingView.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/17/26.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct OnboardingView: View {

    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding = false
    @State private var currentPage = 0
    @State private var showRolePicker = false

    var body: some View {
        if showRolePicker {
            RolePickerView()
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            onboardingContent
        }
    }

    private var onboardingContent: some View {
        ZStack {

            // Background — matches app cloud white
            TBTheme.cloudWhite.ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: Top Bar
                HStack {
                    Image("TenBelowLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)

                    Spacer()

                    if currentPage < 2 {
                        Button("Skip") {
                            #if os(iOS)
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            #endif
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                showRolePicker = true
                            }
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(TBTheme.skyBlue)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // MARK: Pages
                TabView(selection: $currentPage) {

                    OnboardingPage(
                        imageName: "filament_image",
                        title: "Fresh Ideas Start Here",
                        subtitle: "High-quality filament. Clean prints.\nDesigned to last.",
                        isActive: currentPage == 0
                    )
                    .tag(0)

                    OnboardingPage(
                        imageName: "printer_image",
                        title: "Made Just For You",
                        subtitle: "Every item is printed on demand —\nprecision, layer by layer.",
                        isActive: currentPage == 1
                    )
                    .tag(1)

                    OnboardingPage(
                        imageName: "products_image",
                        title: "Small Prices. Big Wins.",
                        subtitle: "Functional, creative, and shipped to your door — all $10 and under.",
                        isActive: currentPage == 2
                    )
                    .tag(2)
                }
                #if os(iOS) || os(visionOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .animation(.easeInOut(duration: 0.35), value: currentPage)

                // MARK: Page Dots
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? TBTheme.accent : TBTheme.skyLight)
                            .frame(width: index == currentPage ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.35), value: currentPage)
                    }
                }
                .padding(.bottom, 28)

                // MARK: Buttons
                if currentPage < 2 {
                    Button {
                        #if os(iOS)
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        #endif
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentPage += 1
                        }
                    } label: {
                        Text("Continue")
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    .padding(.horizontal, 32)
                    .padding(.bottom, 44)
                } else {
                    Button {
                        #if os(iOS)
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        #endif

                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            showRolePicker = true
                        }
                    } label: {
                        Text("Start Exploring")
                    }
                    .buttonStyle(GlassPillButtonStyle(isFinal: true))
                    .padding(.horizontal, 32)
                    .padding(.bottom, 44)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
}
