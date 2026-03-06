import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RolePickerView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("userRole") private var userRole = ""

    var body: some View {
        ZStack {
            TBTheme.cloudWhite.ignoresSafeArea()

            VStack(spacing: 0) {
                Image("TenBelowLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
                    .padding(.top, 24)

                Spacer()

                Text("How will you use\nTenBelow?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(TBTheme.frostTitleGradient)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)

                Text("You can always change this later in Settings.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 36)

                VStack(spacing: TBTheme.spacingLG) {
                    roleCard(
                        icon: "cart.fill",
                        title: "I'm Shopping",
                        description: "Browse 3D-printed products under $10, discover sellers, and get items shipped to your door.",
                        role: "buyer"
                    )

                    roleCard(
                        icon: "storefront.fill",
                        title: "I'm Selling",
                        description: "List your 3D-printed products on TenBelow and reach thousands of buyers.",
                        role: "seller"
                    )
                }
                .padding(.horizontal, 24)

                Spacer()
                Spacer()
            }
        }
    }

    private func roleCard(icon: String, title: String, description: String, role: String) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                userRole = role
                hasSeenOnboarding = true
            }
        } label: {
            HStack(spacing: TBTheme.spacingLG) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [TBTheme.skyLight, TBTheme.skyBlue.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(TBTheme.deepSky)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(TBTheme.deepSky)

                    Text(description)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TBTheme.skyBlue)
            }
            .padding(TBTheme.spacingLG)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: TBTheme.radiusXL))
            .overlay(
                RoundedRectangle(cornerRadius: TBTheme.radiusXL)
                    .strokeBorder(TBTheme.skyBlue.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: TBTheme.deepSky.opacity(0.06), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RolePickerView()
}
