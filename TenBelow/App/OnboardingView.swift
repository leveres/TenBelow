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

struct IntroSlide: Identifiable {
    let id: Int
    let imageName: String
    let symbolName: String
    let title: String
    let subtitle: String
}

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding = false
    @AppStorage("userRole") private var userRole = ""
    @AppStorage("shouldShowHomeEntrySplash") private var shouldShowHomeEntrySplash = false
    @AppStorage("pendingLaunchTab") private var pendingLaunchTab = 0
    @State private var currentPage = 0

    var body: some View {
        onboardingContent
    }

    private var slides: [IntroSlide] {
        if userRole == "seller" {
            return [
                IntroSlide(
                    id: 0,
                    imageName: "seller_categories",
                    symbolName: "shippingbox.circle.fill",
                    title: "Launch products buyers want",
                    subtitle: "Desk accessories, organizers,\nand gift-ready 3D-printed items."
                ),
                IntroSlide(
                    id: 1,
                    imageName: "seller_workflow",
                    symbolName: "percent",
                    title: "Create, upload, ship",
                    subtitle: "Set up your shop, add clear media,\nand fulfill each order smoothly."
                ),
                IntroSlide(
                    id: 2,
                    imageName: "seller_perks",
                    symbolName: "square.and.arrow.up.fill",
                    title: "Build early, stay ready",
                    subtitle: "Set up your storefront now and be ready\nfor upcoming seller tools."
                )
            ]
        }

        return [
            IntroSlide(
                id: 0,
                imageName: "filament_image",
                symbolName: "cube.fill",
                title: "Fresh ideas start here",
                subtitle: "Quality filament. Clean prints.\nBuilt to last."
            ),
            IntroSlide(
                id: 1,
                imageName: "printer_image",
                symbolName: "printer.fill",
                title: "Made for you",
                subtitle: "Each item is printed on demand,\nwith precision in every layer."
            ),
            IntroSlide(
                id: 2,
                imageName: "products_image",
                symbolName: "gift.fill",
                title: "Small prices, smart finds",
                subtitle: "Functional, creative products shipped to your door.\nAll $10 and under."
            )
        ]
    }

    private var lastPageIndex: Int {
        max(slides.count - 1, 0)
    }

    private var finalCTA: String {
        userRole == "seller" ? "Start Selling" : "Start Exploring"
    }

    private var onboardingContent: some View {
        ZStack {
            WinterSceneBackground()

            IntroSlidesContent(
                slides: slides,
                currentPage: $currentPage,
                finalCTA: finalCTA,
                onSkip: completeOnboarding,
                onContinue: advanceOnboarding
            )
        }
    }

    private func advanceOnboarding() {
        if currentPage < lastPageIndex {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentPage += 1
            }
        } else {
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.28)) {
            shouldShowHomeEntrySplash = true
            pendingLaunchTab = userRole == "seller" ? 1 : 0
            hasSeenOnboarding = true
        }
    }
}

#Preview {
    OnboardingView()
}

struct IntroSlidesContent: View {
    let slides: [IntroSlide]
    @Binding var currentPage: Int
    let finalCTA: String
    let onSkip: () -> Void
    let onContinue: () -> Void

    private var lastPageIndex: Int {
        max(slides.count - 1, 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image("TenBelowLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 72, alignment: .leading)

                Spacer()

                if currentPage < lastPageIndex {
                    Button("Skip") {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onSkip()
                    }
                    .buttonStyle(
                        PremiumGlassPillButtonStyle(
                            expandsToFullWidth: false,
                            horizontalPadding: 18,
                            verticalPadding: 10,
                            fontSize: 15
                        )
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            TabView(selection: $currentPage) {
                ForEach(slides) { slide in
                    OnboardingPage(
                        imageName: slide.imageName,
                        symbolName: slide.symbolName,
                        title: slide.title,
                        subtitle: slide.subtitle,
                        isActive: currentPage == slide.id
                    )
                    .tag(slide.id)
                }
            }
            #if os(iOS) || os(visionOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .animation(.easeInOut(duration: 0.35), value: currentPage)

            HStack(spacing: 6) {
                ForEach(Array(slides.indices), id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? TBTheme.deepSky : Color.secondary.opacity(0.2))
                        .frame(width: index == currentPage ? 8 : 6, height: index == currentPage ? 8 : 6)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }
            .padding(.bottom, 24)

            Button {
                #if os(iOS)
                let generator = UIImpactFeedbackGenerator(style: currentPage < lastPageIndex ? .light : .medium)
                generator.impactOccurred()
                #endif
                onContinue()
            } label: {
                Text(currentPage < lastPageIndex ? "Continue" : finalCTA)
            }
            .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: currentPage == lastPageIndex))
            .frame(width: 200)
            .padding(.bottom, 44)
            .transition(.scale.combined(with: .opacity))
        }
    }
}
