import Foundation

enum DropCountdown {
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
}
