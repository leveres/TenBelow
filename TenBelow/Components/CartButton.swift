//
//  CartButton.swift
//  TenBelow
//
//  Created by Steven  LeVere on 2/15/26.
//

import SwiftUI

struct CartButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let itemCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                cartIcon
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(TBTheme.deepSky)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .offset(y: 1)

                if itemCount > 0 {
                    Text("\(min(itemCount, 99))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, itemCount >= 10 ? 5 : 4)
                        .padding(.vertical, 3)
                        .background(TBTheme.accent, in: Capsule())
                        .padding(.top, 2)
                        .padding(.trailing, 0)
                        .contentTransition(.numericText())
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.82).combined(with: .opacity))
                }
            }
            // Room for the badge inside layout bounds (avoids nav bar clipping when a glass capsule is used).
            .frame(width: 48, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tbAnimation(TBMotion.success, value: itemCount)
        .accessibilityLabel("Open cart")
        .accessibilityValue("\(itemCount) item\(itemCount == 1 ? "" : "s")")
    }

    @ViewBuilder
    private var cartIcon: some View {
        if reduceMotion {
            Image(systemName: "cart.fill")
        } else {
            Image(systemName: "cart.fill")
                .symbolEffect(.bounce.down, value: itemCount)
        }
    }
}

