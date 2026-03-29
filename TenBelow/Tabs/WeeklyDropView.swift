import SwiftUI

struct WeeklyDropView: View {
    @State private var showProductionPreview: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Hero
                WeeklyDropHero()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Status strip
                WeeklyDropStatusStrip()
                    .padding(.horizontal, 16)

                // Product spotlight
                WeeklyDropSpotlightCard()
                    .padding(.horizontal, 16)

                // Craft story
                WeeklyDropCraftStory(onSeeProcess: {
                    showProductionPreview = true
                })
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .background(Color.blue.opacity(0.03).ignoresSafeArea())
        .navigationTitle("Weekly Drop")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showProductionPreview) {
            NavigationStack {
                // Placeholder sheet content; hook actual video later.
                VStack(spacing: 16) {
                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Production preview coming soon")
                        .font(.headline)
                    Text("Wire this to your production preview video when available.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .navigationTitle("Production Preview")
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            }
        }
    }
}

// MARK: - Hero

private struct WeeklyDropHero: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Full-bleed hero image with gradient overlay
            Image("WeeklyDropHero")
                .resizable()
                .scaledToFill()
                .frame(height: 260)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.0), Color.black.opacity(0.45)],
                        startPoint: .center, endPoint: .bottom
                    )
                )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    PremiumGlassBadge(title: "Drop 12", subtitle: "Mar 29")
                    PremiumGlassBadge(title: "Limited", subtitle: "250 pcs")
                }

                Text("Aurora Filament Series")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text("Iridescent hues, precision finish, winter-forged.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .padding(16)
        }
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 18)
    }
}

// Optional parallax version if needed elsewhere.
private struct ParallaxWeeklyDropHero: View {
    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .global).minY
            Image("WeeklyDropHero")
                .resizable()
                .scaledToFill()
                .frame(height: 260 + max(0, minY))
                .offset(y: min(0, -minY))
        }
        .frame(height: 260)
        .clipped()
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 18)
    }
}

// MARK: - Status Strip

private struct WeeklyDropStatusStrip: View {
    var body: some View {
        GlassCard(cornerRadius: 18) {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TBTheme.icyBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Available for 6 days")
                        .font(.tbBodyStrong)
                    Text("72% claimed • Ships next week")
                        .font(.tbCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
    }
}

// MARK: - Spotlight Card

private struct WeeklyDropSpotlightCard: View {
    var body: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(
                            colors: [TBTheme.icyBlue.opacity(0.18), TBTheme.skyBlue.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(TBTheme.skyBlue.opacity(0.15), lineWidth: 1)
                        )

                    Image("DropPrimaryProduct")
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                        .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 18)
                }
                .frame(height: 180)
                .overlay(alignment: .topTrailing) {
                    PremiumGlassBadge(title: "New", subtitle: "Just dropped")
                        .padding(10)
                }

                Text("Polar Night PLA+")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("High-flow clarity, low-temp sheen, tuned for dimensional accuracy.")
                    .font(.tbBody)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("$24.00")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(TBTheme.deepSky)
                    Spacer()
                    Button {
                        // TODO: Hook to product detail or add-to-cart
                    } label: {
                        Label("Shop now", systemImage: "sparkles")
                            .font(.tbBodyStrong)
                    }
                    .buttonStyle(PremiumGlassPillButtonStyle(isEmphasized: true, horizontalPadding: 18, verticalPadding: 10, fontSize: 15))
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Craft Story

private struct WeeklyDropCraftStory: View {
    var onSeeProcess: () -> Void

    var body: some View {
        GlassCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Label("The Craft", systemImage: "snowflake")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("Cold-forged clarity, tuned for precision")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("Each batch is conditioned in sub-zero chambers, resulting in a smoother extrusion and a glass-like finish on overhangs and curves.")
                    .font(.tbBody)
                    .foregroundStyle(.secondary)

                Button(action: onSeeProcess) {
                    Label("See the process", systemImage: "sparkles.tv.fill")
                        .font(.tbBodyStrong)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Premium Glass Badge

private struct PremiumGlassBadge: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.tbBodyStrong)
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.tbCaption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

#Preview {
    NavigationStack {
        WeeklyDropView()
    }
}
