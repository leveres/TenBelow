import SwiftUI

struct MetricChip: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.8))
                    .frame(
                        width: dynamicTypeSize.isAccessibilitySize ? 40 : 34,
                        height: dynamicTypeSize.isAccessibilitySize ? 40 : 34
                    )
                Image(systemName: icon)
                    .font(dynamicTypeSize.isAccessibilitySize ? .title3.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(TBTheme.deepSky)
                    .symbolRenderingMode(.hierarchical)
            }

            Text(value)
                .font(dynamicTypeSize.isAccessibilitySize ? .title2.weight(.bold) : .title3.weight(.bold))
                .foregroundStyle(TBTheme.deepSky)
                .minimumScaleFactor(0.85)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TBTheme.spacingMD)
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: TBTheme.radiusLG))
        .overlay(
            RoundedRectangle(cornerRadius: TBTheme.radiusLG)
                .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.03), radius: 8, y: 4)
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
