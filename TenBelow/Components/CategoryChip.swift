//
//  CategoryChip.swift
//  TenBelow
//

import SwiftUI

struct CategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? TBTheme.skyBlue.opacity(0.12) : Color.white.opacity(0.72))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(isSelected ? TBTheme.deepSky.opacity(0.18) : TBTheme.skyBlue.opacity(0.10), lineWidth: 0.8)
        )
        .foregroundStyle(isSelected ? TBTheme.deepSky : Color.primary.opacity(0.85))
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
        .contentShape(Capsule())
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}
