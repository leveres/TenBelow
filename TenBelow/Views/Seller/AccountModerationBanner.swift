import SwiftUI

struct AccountModerationBanner: View {
    let status: AccountModerationStatus

    private var iconName: String {
        status.isFrozen ? "snowflake.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var tint: Color {
        status.isFrozen ? Color(red: 0.25, green: 0.39, blue: 0.84) : Color.orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 6) {
                    Text(status.headline)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)

                    Text(status.detailMessage)
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(status.supportFooter)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.24), lineWidth: 1)
        )
    }
}
