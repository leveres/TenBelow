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
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        selected = category
                    } label: {
                        CategoryChip(
                            title: category.title,
                            icon: category.icon,
                            isSelected: selected == category
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}
