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
            ZStack {
                Circle()
                    .fill(.white.opacity(0.8))
                    .frame(width: 30, height: 30)
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 30, alignment: .center)

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
                .fill(.white.opacity(0.72))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.03), radius: 8, y: 4)
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
