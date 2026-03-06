import SwiftUI

struct MetricChip: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TBTheme.icyBlue)
                .shadow(color: TBTheme.icyBlue.opacity(0.30), radius: 3, y: 2)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(TBTheme.deepSky)
                .shadow(color: TBTheme.skyBlue.opacity(0.20), radius: 2, y: 1)

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TBTheme.spacingMD)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.50), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: TBTheme.radiusLG))
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.6), TBTheme.skyBlue.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: TBTheme.deepSky.opacity(0.06), radius: 8, y: 3)
        .shadow(color: TBTheme.skyBlue.opacity(0.03), radius: 1, y: 1)
    }
}

#Preview {
    HStack(spacing: 12) {
        MetricChip(title: "Products", value: "12", icon: "cube.fill")
        MetricChip(title: "Orders", value: "48", icon: "shippingbox.fill")
        MetricChip(title: "Rating", value: "4.9", icon: "star.fill")
    }
    .padding()
    .background(TBTheme.cloudWhite)
}
