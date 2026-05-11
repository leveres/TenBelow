import Foundation

struct WeekendDropSchedule: Equatable {
    let previewStartsAt: Date
    let startsAt: Date
    let submissionsLockAt: Date
    let endsAt: Date
}

struct WeekendDropState: Equatable {
    enum Phase: Equatable {
        case upcoming
        case thursdayPreview
        case liveSubmissionsOpen
        case liveSubmissionsLocked
        case closed
    }

    let phase: Phase
    let schedule: WeekendDropSchedule
    let headline: String
    let promoPhrases: [String]
    let itemCount: Int
    let accentSymbolName: String
    let usesPreviewData: Bool

    var isUpcoming: Bool { phase == .upcoming }
    var isThursdayPreview: Bool { phase == .thursdayPreview }
    var isLive: Bool { phase == .liveSubmissionsOpen || phase == .liveSubmissionsLocked }
    var areSubmissionsOpen: Bool { phase == .thursdayPreview || phase == .liveSubmissionsOpen }
    var areSubmissionsLocked: Bool { phase == .liveSubmissionsLocked }
    var isClosed: Bool { phase == .closed }

    var itemCountLabel: String {
        "\(itemCount) item\(itemCount == 1 ? "" : "s")"
    }

    func countdownTitle(now: Date) -> String {
        switch phase {
        case .upcoming:
            return "Starts In"
        case .thursdayPreview:
            return "Starts In"
        case .liveSubmissionsOpen:
            return now < schedule.submissionsLockAt ? "Locks In" : "Ends In"
        case .liveSubmissionsLocked:
            return "Ends In"
        case .closed:
            return "Next Drop"
        }
    }

    func countdownText(now: Date) -> String {
        switch phase {
        case .upcoming:
            return DropCountdown.digitalCountdown(until: schedule.startsAt, now: now)
        case .thursdayPreview:
            return DropCountdown.digitalCountdown(until: schedule.startsAt, now: now)
        case .liveSubmissionsOpen:
            return DropCountdown.digitalCountdown(until: min(schedule.submissionsLockAt, schedule.endsAt), now: now)
        case .liveSubmissionsLocked:
            return DropCountdown.digitalCountdown(until: schedule.endsAt, now: now)
        case .closed:
            return DropCountdown.digitalCountdown(until: schedule.startsAt, now: now)
        }
    }

    /// Full precision (includes seconds under 24h) — only for the live shopping window.
    var usesTickingDropCountdown: Bool {
        switch phase {
        case .liveSubmissionsOpen, .liveSubmissionsLocked:
            return true
        case .upcoming, .thursdayPreview, .closed:
            return false
        }
    }

    /// Timer pill: tick every second only while the drop is live; otherwise show time-to-event without seconds.
    func countdownDisplayText(now: Date) -> String {
        if usesTickingDropCountdown {
            return countdownText(now: now)
        }
        switch phase {
        case .upcoming:
            return DropCountdown.digitalCountdownNoSeconds(until: schedule.startsAt, now: now)
        case .thursdayPreview:
            return DropCountdown.digitalCountdownNoSeconds(until: schedule.startsAt, now: now)
        case .liveSubmissionsOpen, .liveSubmissionsLocked:
            return countdownText(now: now)
        case .closed:
            return DropCountdown.digitalCountdownNoSeconds(until: schedule.startsAt, now: now)
        }
    }
}

enum WeekendDropAudience {
    /// Shopping-focused copy on the Weekly Drop tab.
    case buyer
    /// Seller submission windows, locks, and ops language.
    case seller
}

enum WeekendDropManager {
    private static let isoFormatter = ISO8601DateFormatter()
    private static let easternTimeZone = TimeZone(identifier: "America/New_York") ?? .current

    static func state(
        now: Date = .now,
        currentDrop: CurrentDropResponse?,
        products: [DropProduct],
        calendar: Calendar = .current,
        audience: WeekendDropAudience = .seller
    ) -> WeekendDropState {
        let schedule = resolvedSchedule(now: now, currentDrop: currentDrop, calendar: calendar)
        let phase = resolvedPhase(now: now, schedule: schedule)

        return WeekendDropState(
            phase: phase,
            schedule: schedule,
            headline: headline(for: phase, audience: audience),
            promoPhrases: promoPhrases(for: phase, audience: audience),
            itemCount: includedItemCount(products: products, phase: phase, schedule: schedule, now: now),
            accentSymbolName: accentSymbol(for: phase),
            usesPreviewData: false
        )
    }

    static func isSubmissionWindowOpen(
        now: Date = .now,
        currentDrop: CurrentDropResponse? = nil,
        calendar: Calendar = .current
    ) -> Bool {
        let schedule = resolvedSchedule(now: now, currentDrop: currentDrop, calendar: calendar)
        let phase = resolvedPhase(now: now, schedule: schedule)
        return phase == .thursdayPreview || phase == .liveSubmissionsOpen
    }

    /// Next weekly drop start used when the API omits `nextDropAt` (Friday 12:00 AM for the upcoming cycle).
    static func nextScheduledWeeklyDropStart(
        now: Date = .now,
        currentDrop: CurrentDropResponse? = nil,
        calendar: Calendar = .current
    ) -> Date {
        let schedule = resolvedSchedule(now: now, currentDrop: currentDrop, calendar: calendar)
        let phase = resolvedPhase(now: now, schedule: schedule)
        switch phase {
        case .upcoming, .thursdayPreview:
            return schedule.startsAt
        case .liveSubmissionsOpen, .liveSubmissionsLocked, .closed:
            return calendar.date(byAdding: .day, value: 7, to: schedule.startsAt) ?? schedule.startsAt
        }
    }

    private static func resolvedSchedule(
        now: Date,
        currentDrop: CurrentDropResponse?,
        calendar: Calendar
    ) -> WeekendDropSchedule {
        let easternCalendar = calendarWithEasternTimeZone(from: calendar)

        if let currentDrop,
           let startsAt = isoFormatter.date(from: currentDrop.startsAt),
           let endsAt = isoFormatter.date(from: currentDrop.endsAt) {
            let liveStart = easternCalendar.startOfDay(for: startsAt)
            return WeekendDropSchedule(
                previewStartsAt: easternCalendar.date(byAdding: DateComponents(day: -1, hour: 17), to: liveStart) ?? liveStart,
                startsAt: liveStart,
                submissionsLockAt: liveStart,
                endsAt: endsAt
            )
        }

        let cycleStart = resolvedCycleStart(now: now, calendar: easternCalendar)

        return WeekendDropSchedule(
            previewStartsAt: easternCalendar.date(byAdding: DateComponents(day: -1, hour: 17), to: cycleStart) ?? cycleStart,
            startsAt: cycleStart,
            submissionsLockAt: cycleStart,
            endsAt: easternCalendar.date(byAdding: DateComponents(day: 3, second: -1), to: cycleStart) ?? cycleStart
        )
    }

    private static func resolvedCycleStart(now: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: startOfToday)
        let daysSinceFriday = (weekday - 6 + 7) % 7
        let mostRecentFridayStart = calendar.date(byAdding: .day, value: -daysSinceFriday, to: startOfToday) ?? startOfToday
        let mostRecentSubmissionStart = calendar.date(byAdding: DateComponents(day: -1, hour: 17), to: mostRecentFridayStart) ?? mostRecentFridayStart
        let mostRecentWeekendEnd = calendar.date(byAdding: DateComponents(day: 3, second: -1), to: mostRecentFridayStart) ?? mostRecentFridayStart

        if now >= mostRecentSubmissionStart, now <= mostRecentWeekendEnd {
            return mostRecentFridayStart
        }

        return calendar.date(byAdding: .day, value: 7, to: mostRecentFridayStart) ?? mostRecentFridayStart
    }

    private static func calendarWithEasternTimeZone(from calendar: Calendar) -> Calendar {
        var easternCalendar = calendar
        easternCalendar.timeZone = easternTimeZone
        return easternCalendar
    }

    private static func resolvedPhase(now: Date, schedule: WeekendDropSchedule) -> WeekendDropState.Phase {
        if now < schedule.previewStartsAt {
            return .upcoming
        }
        if now < schedule.startsAt {
            return .thursdayPreview
        }
        if now <= schedule.endsAt {
            return now < schedule.submissionsLockAt ? .liveSubmissionsOpen : .liveSubmissionsLocked
        }
        return .closed
    }

    private static func includedItemCount(
        products: [DropProduct],
        phase: WeekendDropState.Phase,
        schedule: WeekendDropSchedule,
        now: Date
    ) -> Int {
        let cutoffDate: Date
        switch phase {
        case .upcoming:
            cutoffDate = schedule.previewStartsAt
        case .thursdayPreview, .liveSubmissionsOpen:
            cutoffDate = now
        case .liveSubmissionsLocked, .closed:
            cutoffDate = schedule.submissionsLockAt
        }

        return products.filter { product in
            guard let submittedAt = isoFormatter.date(from: product.submittedAt) else {
                return true
            }
            return submittedAt <= cutoffDate
        }.count
    }

    private static func headline(for phase: WeekendDropState.Phase, audience: WeekendDropAudience) -> String {
        switch phase {
        case .upcoming:
            return "Next drop starts soon"
        case .thursdayPreview:
            return "Next drop starts soon"
        case .liveSubmissionsOpen:
            return audience == .buyer ? "Weekend drop is live" : "Submitting for this weekend"
        case .liveSubmissionsLocked:
            return "Products live this weekend!"
        case .closed:
            return "This weekend drop closed"
        }
    }

    private static func promoPhrases(for phase: WeekendDropState.Phase, audience: WeekendDropAudience) -> [String] {
        switch phase {
        case .upcoming:
            return [
                "Friday at 12 AM",
                "Premium creator releases",
                "Weekend lineup opens soon",
                "Fresh picks land this weekend"
            ]
        case .thursdayPreview:
            if audience == .buyer {
                return [
                    "Starts Friday at 12 AM",
                    "Premium creator releases",
                    "Weekend shopping opens soon"
                ]
            }
            return [
                "Submit by 11:59 PM ET",
                "Starts Friday at 12 AM",
                "Premium creator releases",
                "Creators can still prep submissions"
            ]
        case .liveSubmissionsOpen:
            if audience == .buyer {
                return [
                    "Premium creator releases",
                    "Limited weekend drop",
                    "New designs just landed",
                    "Shop through Sunday night"
                ]
            }
            return [
                "Locking at 12 PM",
                "Premium creator releases",
                "Limited weekend drop",
                "New designs just landed"
            ]
        case .liveSubmissionsLocked:
            return [
                "Premium creator releases",
                "Limited weekend drop",
                "New designs just landed"
            ]
        case .closed:
            return [
                "This weekend lineup has closed",
                "Next drop cycle is being prepared",
                "Fresh creator picks return Thursday evening",
                "Check back for the next preview"
            ]
        }
    }

    private static func accentSymbol(for phase: WeekendDropState.Phase) -> String {
        switch phase {
        case .upcoming:
            return "calendar.badge.clock"
        case .thursdayPreview:
            return "eye.fill"
        case .liveSubmissionsOpen:
            return "sparkles"
        case .liveSubmissionsLocked:
            return "lock.fill"
        case .closed:
            return "moon.stars.fill"
        }
    }
}
