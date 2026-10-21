import Foundation

/// Text formatting shared by the iPad UI and the Mac agent.
public enum Format {
    /// "now", "4m", "2h", "3d".
    public static func shortDuration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return s < 5 ? "now" : "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }

    /// "4m ago", "just now".
    public static func ago(_ date: Date, now: Date = .now) -> String {
        let d = shortDuration(now.timeIntervalSince(date))
        return d == "now" ? "just now" : "\(d) ago"
    }

    /// "0:42", "1:03:09".
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "182k", "1.2M".
    public static func tokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1000 { return "\(count / 1000)k" }
        return "\(count)"
    }

    /// "Two sessions are working" style counts.
    public static func spelled(_ n: Int) -> String {
        let words = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]
        return n < words.count ? words[n] : "\(n)"
    }
}
