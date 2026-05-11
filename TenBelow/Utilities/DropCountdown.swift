import Foundation

enum DropCountdown {
    /// Single headline for the inactive Weekly Drop card: "Next drop opens in 4 days".
    static func inactiveBuyerNextDropHeadline(
        nextDropAtISO: String?,
        now: Date,
        currentDrop: CurrentDropResponse?
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let target: Date
        if let nextDropAtISO, let parsed = formatter.date(from: nextDropAtISO), parsed > now {
            target = parsed
        } else {
            target = WeekendDropManager.nextScheduledWeeklyDropStart(now: now, currentDrop: currentDrop)
        }

        guard target > now else {
            return "Next drop opens soon"
        }

        let calendar = Calendar.current
        let comps = calendar.dateComponents([.day, .hour, .minute], from: now, to: target)
        let d = comps.day ?? 0
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0

        if d >= 2 {
            return "Next drop opens in \(d) days"
        }
        if d == 1 {
            return "Next drop opens in 1 day"
        }
        if h >= 2 {
            return "Next drop opens in \(h) hours"
        }
        if h == 1 {
            return "Next drop opens in 1 hour"
        }
        if m >= 2 {
            return "Next drop opens in \(m) minutes"
        }
        if m == 1 {
            return "Next drop opens in 1 minute"
        }
        return "Next drop opens soon"
    }

    static func timeLeft(until isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let endDate = formatter.date(from: isoString) else { return "Ending soon" }
        let now = Date()
        if endDate <= now { return "Drop ended" }

        let comps = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: endDate)
        let d = comps.day ?? 0
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0

        if d > 0 { return "\(d)d left" }
        if h > 0 { return "\(h)h left" }
        return "\(m)m left"
    }

    static func digitalCountdown(until isoString: String, now: Date = .now) -> String {
        let formatter = ISO8601DateFormatter()
        guard let endDate = formatter.date(from: isoString) else { return "00:00:00" }
        return digitalCountdown(until: endDate, now: now)
    }

    static func digitalCountdown(until endDate: Date, now: Date = .now) -> String {
        let remaining = max(Int(endDate.timeIntervalSince(now)), 0)
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60

        if days > 0 {
            return String(format: "%02dd %02dh %02dm", days, hours, minutes)
        }

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Same as `digitalCountdown`, but never shows seconds (used before/after the live drop window).
    static func digitalCountdownNoSeconds(until endDate: Date, now: Date = .now) -> String {
        let remaining = max(Int(endDate.timeIntervalSince(now)), 0)
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 {
            return String(format: "%02dd %02dh %02dm", days, hours, minutes)
        }

        return String(format: "%02dh %02dm", hours, minutes)
    }
}
