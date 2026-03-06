import SwiftUI

struct SellerBadge: View {
    let text: String
    let icon: String
    var tint: Color = TBTheme.icyBlue

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .shadow(color: tint.opacity(0.30), radius: 2, y: 1)

            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .shadow(color: tint.opacity(0.20), radius: 2, y: 1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            ZStack {
                Capsule().fill(tint.opacity(0.08))
                Capsule().fill(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        )
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.55), tint.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
        )
        .clipShape(Capsule())
        .shadow(color: tint.opacity(0.10), radius: 3, y: 2)
    }
}

#Preview {
    VStack(spacing: 12) {
        SellerBadge(text: "Ships in 2–4 days", icon: "shippingbox")
        SellerBadge(text: "Ships from Austin, TX", icon: "location.fill")
        SellerBadge(text: "Verified Seller", icon: "checkmark.seal.fill", tint: .green)
    }
    .padding()
    .background(TBTheme.cloudWhite)
}
