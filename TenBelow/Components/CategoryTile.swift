//
//  CategoryTile.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI

struct CategoryTile: View {
    let category: TBCategory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TBTheme.deepSky)
                .frame(width: 24, alignment: .center)

            Text(category.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.7),
                            TBTheme.skyBlue.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: TBTheme.deepSky.opacity(0.06), radius: 8, y: 4)
    }
}

#Preview {
    VStack(spacing: 10) {
        ForEach(tbCategories) { cat in
            CategoryTile(category: cat)
        }
    }
    .padding()
}
