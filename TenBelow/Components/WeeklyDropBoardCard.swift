import SwiftUI
import Combine

struct WeeklyDropBoardCard: View {
    let state: WeekendDropState
    /// Fixed clock for previews; live UI ticks internally so the Drop tab body does not re-render every second.
    var referenceNow: Date? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tbTabIsActive) private var tabIsActive
    @State private var liveNow = Date()
    @State private var itemCountScale: CGFloat = 1

    private var now: Date { referenceNow ?? liveNow }

    private enum Metrics {
        static let minimumHeight: CGFloat = 0
        static let maximumWidth: CGFloat = 640
        static let contentHorizontalPadding: CGFloat = 15
        static let contentVerticalPadding: CGFloat = 8
        static let sectionSpacing: CGFloat = 8
        static let textStackSpacing: CGFloat = 2
        static let footerPillSpacing: CGFloat = 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: Metrics.textStackSpacing) {
                GlowingHeadlineText(text: state.headline)
                RotatingPromoText(phrases: state.promoPhrases)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Metrics.footerPillSpacing) {
                countdownPill
                Spacer(minLength: 8)
                itemCountPill
            }
        }
        .padding(.horizontal, Metrics.contentHorizontalPadding)
        .padding(.vertical, Metrics.contentVerticalPadding)
        .frame(maxWidth: Metrics.maximumWidth, minHeight: Metrics.minimumHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(livePulseOverlay)
        .overlay(cardBorder)
        .shadow(color: TBTheme.deepSky.opacity(0.1), radius: 8, y: 3)
        .onReceive(liveCountdownTimer) { tick in
            guard referenceNow == nil, tabIsActive else { return }
            liveNow = tick
        }
        .onChange(of: state.itemCount) { _, _ in
            animateItemCountPop()
        }
    }

    private var liveCountdownTimer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    }

    private var countdownPill: some View {
        Label(state.countdownDisplayText(now: now), systemImage: "timer")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(TBTheme.accent.opacity(0.94))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
            )
            .overlay {
                if isUrgencyCountdown {
                    Capsule(style: .continuous)
                        .strokeBorder(TBTheme.cloudWhite.opacity(0.18), lineWidth: 1)
                }
            }
            .accessibilityLabel("\(state.countdownTitle(now: now)) \(state.countdownDisplayText(now: now))")
    }

    private var itemCountPill: some View {
        Label(state.itemCountLabel, systemImage: "shippingbox.fill")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(TBTheme.bannerCTAForeground)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.94))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.48), lineWidth: 0.8)
            )
            .scaleEffect(itemCountScale)
            .accessibilityLabel("\(state.itemCountLabel) included in the weekend drop")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: TBTheme.radiusXL, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        TBTheme.deepSky.opacity(0.9),
                        TBTheme.skyBlue.opacity(0.88),
                        TBTheme.skyBlue.opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: TBTheme.radiusXL, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.08),
                                .clear,
                                .black.opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 132, height: 132)
                    .offset(x: -26, y: -48)
            }
            .overlay(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.04))
                    .frame(width: 128, height: 48)
                    .offset(x: 20, y: 14)
            }
            .overlay {
                RoundedRectangle(cornerRadius: TBTheme.radiusXL - 2, style: .continuous)
                    .strokeBorder(.white.opacity(0.05), lineWidth: 0.6)
                    .padding(6)
            }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: TBTheme.radiusXL, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear, .white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    @ViewBuilder
    private var livePulseOverlay: some View {
        if state.isLive {
            RoundedRectangle(cornerRadius: TBTheme.radiusXL, style: .continuous)
                .strokeBorder(TBTheme.skyLight.opacity(0.2), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var countdownTargetDate: Date {
        switch state.phase {
        case .upcoming, .thursdayPreview:
            return state.schedule.startsAt
        case .liveSubmissionsOpen:
            return min(state.schedule.submissionsLockAt, state.schedule.endsAt)
        case .liveSubmissionsLocked:
            return state.schedule.endsAt
        case .closed:
            return state.schedule.startsAt
        }
    }

    private var isUrgencyCountdown: Bool {
        state.isLive && countdownTargetDate.timeIntervalSince(now) <= 3600
    }

    private func animateItemCountPop() {
        guard !reduceMotion else { return }
        itemCountScale = 1.08
        withAnimation(TBMotion.press) {
            itemCountScale = 1
        }
    }
}

struct GlowingHeadlineText: View {
    let text: String

    var body: some View {
        Text(text)
            .glowingBubbleHeadlineStyle()
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .multilineTextAlignment(.leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct RotatingPromoText: View {
    let phrases: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tbTabIsActive) private var tabIsActive
    @State private var activePhraseIndex = 0
    @State private var isVisible = false
    private let timer = Timer.publish(every: 3.4, on: .main, in: .common).autoconnect()

    private var currentPhrase: String {
        guard !phrases.isEmpty else { return "" }
        return phrases[min(activePhraseIndex, phrases.count - 1)]
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Text(currentPhrase)
                .id(activePhraseIndex)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.opacity)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
        }
        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        .clipped()
        .tbAnimation(TBMotion.stateChange, value: activePhraseIndex)
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
        .onReceive(timer) { _ in
            guard isVisible, tabIsActive, phrases.count > 1 else { return }
            withAnimation(reduceMotion ? nil : TBMotion.stateChange) {
                activePhraseIndex = (activePhraseIndex + 1) % phrases.count
            }
        }
        .accessibilityLabel(phrases.joined(separator: ", "))
    }
}

private struct GlowingBubbleHeadlineStyle: ViewModifier {
    private let font = Font.system(size: 22, weight: .heavy, design: .rounded)

    func body(content: Content) -> some View {
        content
            .font(font)
            .tracking(-0.8)
            .foregroundStyle(TBTheme.cloudWhite.opacity(0.96))
            .background {
                content
                    .font(font)
                    .tracking(-0.8)
                    .foregroundStyle(TBTheme.skyLight.opacity(0.14))
                    .blur(radius: 2.5)
            }
            .overlay {
                content
                    .font(font)
                    .tracking(-0.8)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                TBTheme.cloudWhite.opacity(0.98),
                                TBTheme.cloudWhite.opacity(0.94),
                                TBTheme.skyLight.opacity(0.82)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .shadow(color: .white.opacity(0.14), radius: 1, y: 0)
            .shadow(color: TBTheme.skyLight.opacity(0.16), radius: 3.5, y: 0)
    }
}

private extension View {
    func glowingBubbleHeadlineStyle() -> some View {
        modifier(GlowingBubbleHeadlineStyle())
    }
}
