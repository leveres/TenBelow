//
//  ShippingProgressBar.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI

struct ShippingProgressBar: View {
    let subtotalCents: Int
    let freeShippingThresholdCents: Int

    private var progress: Double {
        min(Double(subtotalCents) / Double(freeShippingThresholdCents), 1.0)
    }

    private var remainingCents: Int {
        max(freeShippingThresholdCents - subtotalCents, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
            if remainingCents == 0 {
                Text("Free shipping unlocked")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .shadow(color: .green.opacity(0.25), radius: 2, y: 1)
            } else {
                Text("Add **\(Money.format(cents: remainingCents))** for free shipping")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
                    .shadow(color: TBTheme.skyBlue.opacity(0.15), radius: 2, y: 1)
            }

            ProgressView(value: progress)
                .tint(progress >= 1.0 ? .green : TBTheme.accent)
                .animation(nil, value: progress)
        }
        .padding(TBTheme.spacingMD)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .fill(TBTheme.cardGradient)
                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .cornerRadius(TBTheme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.6), TBTheme.skyBlue.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: TBTheme.deepSky.opacity(0.06), radius: 5, y: 3)
    }
}

