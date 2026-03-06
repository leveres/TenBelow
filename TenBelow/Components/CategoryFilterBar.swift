//
//  CategoryFilterBar.swift
//  TenBelow
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct CategoryFilterBar: View {
    let categories: [TBCategory]
    @Binding var selected: TBCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories) { category in
                    CategoryChip(
                        title: category.title,
                        icon: category.icon,
                        isSelected: selected == category
                    )
                    .onTapGesture {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        selected = category
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}
