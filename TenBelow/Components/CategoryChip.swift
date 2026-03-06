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
                .font(.caption)
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? TBTheme.skyBlue.opacity(0.16) : Color.white.opacity(0.55))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(isSelected ? TBTheme.skyBlue.opacity(0.35) : TBTheme.skyBlue.opacity(0.10), lineWidth: 1)
        )
        .foregroundStyle(isSelected ? TBTheme.deepSky : Color.primary.opacity(0.85))
        .shadow(color: .black.opacity(isSelected ? 0.06 : 0.03), radius: 8, x: 0, y: 6)
        .contentShape(Capsule())
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}
