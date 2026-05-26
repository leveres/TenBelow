//
//  AppOperationOverlay.swift
//  TenBelow
//
//  Compact in-flow progress card for account creation, submissions, and similar tasks.
//  Use AppLoadingOverlay only for app-wide bootstrap (splash / initial catalog load).
//

import SwiftUI

struct AppOperationOverlay: View {
    var title: String
    var subtitle: String
    var systemImage: String? = nil
    var showsProgress: Bool = true

    var body: some View {
        VStack(spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(TBTheme.icyBlue)
            } else if showsProgress {
                ProgressView()
                    .controlSize(.large)
                    .tint(TBTheme.deepSky)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.deepSky)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.82), lineWidth: 1)
        )
        .shadow(color: TBTheme.deepSky.opacity(0.12), radius: 20, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
