//
//  OnboardingPage.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/17/26.
//

import SwiftUI

struct OnboardingPage: View {
    let imageName: String
    let title: String
    let subtitle: String
    var isActive: Bool = false

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // Image with frost card backing
            ZStack {
                RoundedRectangle(cornerRadius: TBTheme.radiusXL)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: TBTheme.radiusXL)
                            .strokeBorder(TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: TBTheme.skyBlue.opacity(0.1), radius: 20, y: 10)

                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
            }
            .frame(maxHeight: 280)
            .padding(.horizontal, 40)
            .scaleEffect(isActive ? 1.0 : 0.96)
            .opacity(isActive ? 1.0 : 0.7)
            .animation(.easeInOut(duration: 0.5), value: isActive)

            Spacer()
                .frame(height: 36)

            // Text
            VStack(spacing: TBTheme.spacingMD) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.frostTitleGradient)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 36)
            }

            Spacer()
        }
    }
}

#Preview {
    ZStack {
        TBTheme.cloudWhite.ignoresSafeArea()
        OnboardingPage(
            imageName: "Logo",
            title: "Printed Fresh",
            subtitle: "Every item is 3D-printed when you order. No warehouses, no waste.",
            isActive: true
        )
    }
}
