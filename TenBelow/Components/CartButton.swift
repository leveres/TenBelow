//
//  CartButton.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI

struct CartButton: View {
    let itemCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "cart")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(TBTheme.icyBlue)
                .frame(width: 28, height: 28)
                .overlay(alignment: .topTrailing) {
                    if itemCount > 0 {
                        Text("\(min(itemCount, 99))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 6, y: -6)
                    }
                }
        }
        .accessibilityLabel("Cart, \(itemCount) items")
    }
}

#Preview {
    CartButton(itemCount: 3) { }
}
