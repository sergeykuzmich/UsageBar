import Foundation

public enum RelativeTime {
    public static func untilReset(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now).rounded())
        guard seconds > 30 else { return "resetting now" }
        return "resets in " + compact(seconds)
    }

    public static func sinceUpdate(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date).rounded())
        guard seconds >= 60 else { return "updated just now" }
        return "updated " + compact(seconds) + " ago"
    }

    static func compact(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        if hours < 24 {
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        }
        let days = hours / 24
        let remainder = hours % 24
        return remainder == 0 ? "\(days)d" : "\(days)d \(remainder)h"
    }
}
