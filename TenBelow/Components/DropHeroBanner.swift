//
//  DropHeroBanner.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI

struct DropHeroBanner: View {
    let drop: Drop
    var dropEndsAt: String?
    var cta: String = "View Drop →"

    private var badgeText: String {
        if let endsAt = dropEndsAt, !endsAt.isEmpty {
            return DropCountdown.timeLeft(until: endsAt)
        }
        return "\(drop.daysRemaining) days left"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TBTheme.spacingSM) {
            Text(drop.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .shadow(color: .white.opacity(0.15), radius: 0, y: -0.5)

            Text(drop.subtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.90))
                .shadow(color: .black.opacity(0.20), radius: 3, y: 1)

            Spacer()

            HStack {
                Text(badgeText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.20), radius: 2, y: 1)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        ZStack {
                            Capsule().fill(.white.opacity(0.20))
                            Capsule().fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.30), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    )
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                Spacer()

                Text("\(cta) →")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            }
        }
        .padding(TBTheme.spacingLG)
        .frame(height: 160)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .fill(TBTheme.dropBannerGradient)

                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.12), .clear, .black.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .cornerRadius(TBTheme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: TBTheme.deepSky.opacity(0.20), radius: 12, y: 5)
        .shadow(color: TBTheme.skyBlue.opacity(0.10), radius: 2, y: 1)
    }
}

