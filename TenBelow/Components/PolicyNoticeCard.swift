import SwiftUI

enum PolicyNoticeTone {
    case neutral
    case exchange
    case support
    case caution

    var accent: Color {
        switch self {
        case .neutral: return TBTheme.deepSky
        case .exchange: return TBTheme.icyBlue
        case .support: return TBTheme.deepSky
        case .caution: return Color.orange
        }
    }
}

struct PolicyNoticeCard: View {
    let title: String?
    let bodyText: String
    var tone: PolicyNoticeTone = .neutral

    init(title: String? = nil, bodyText: String, tone: PolicyNoticeTone = .neutral) {
        self.title = title
        self.bodyText = bodyText
        self.tone = tone
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tone.accent.opacity(0.85))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: title == nil ? 0 : 4) {
                if let title {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TBTheme.deepSky)
                }

                Text(bodyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 12)
            .padding(.vertical, 10)
            .padding(.trailing, 12)
        }
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TBTheme.frostEdge, lineWidth: 1)
        )
    }
}

struct PolicyOutlineRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(TBTheme.deepSky.opacity(0.35))
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
