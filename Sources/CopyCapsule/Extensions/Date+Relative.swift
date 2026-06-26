import Foundation

extension Date {
    /// Human-readable relative time description.
    ///
    /// Examples:
    /// - "Just now" (< 1 min)
    /// - "3 min ago" (< 60 min)
    /// - "2 hours ago" (< today)
    /// - "Yesterday" (yesterday)
    /// - "Jun 3" (this year)
    /// - "Jun 3, 2025" (previous year)
    var relative: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        // Future dates (shouldn't happen) → absolute
        guard interval >= 0 else { return formatted(date: .abbreviated, time: .shortened) }

        // < 1 minute
        if interval < 60 { return "Just now" }

        // < 1 hour → minutes
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        }

        // Today → hours
        if Calendar.current.isDateInToday(self) {
            let hours = Int(interval / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }

        // Yesterday
        if Calendar.current.isDateInYesterday(self) {
            return "Yesterday"
        }

        // This year → month + day
        if Calendar.current.component(.year, from: self) == Calendar.current.component(.year, from: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: self)
        }

        // Previous year → month + day + year
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: self)
    }
}
