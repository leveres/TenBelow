import SwiftUI

struct SellerBadge: View {
    let text: String
    let icon: String
    var tint: Color = TBTheme.icyBlue
    /// Tighter padding for dense layouts (e.g. public store header).
    var isCompact: Bool = false

    var body: some View {
        HStack(spacing: isCompact ? 5 : 6) {
            Image(systemName: icon)
                .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(text)
                .font(.system(size: isCompact ? 11 : 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, isCompact ? 10 : 12)
        .padding(.vertical, isCompact ? 5 : 7)
        .background(
            Capsule(style: .continuous)
                .fill(.white.opacity(0.66))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.14), lineWidth: 0.8)
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.03), radius: 8, y: 4)
    }
}

