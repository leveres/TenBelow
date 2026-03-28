import SwiftUI

struct NotificationBellButton: View {
    let unreadCount: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TBTheme.deepSky)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: 1)

            if unreadCount > 0 {
                Text("\(min(unreadCount, 99))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, unreadCount >= 10 ? 5 : 4)
                    .padding(.vertical, 3)
                    .background(TBTheme.accent, in: Capsule())
                    .padding(.top, 2)
                    .padding(.trailing, 0)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Open notifications")
        .accessibilityValue("\(unreadCount) unread")
    }
}

#Preview {
    NotificationBellButton(unreadCount: 4)
}
