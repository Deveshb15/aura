import Foundation

/// Relative-time formatting for item timestamps. Two forms: a terse `compact`
/// for the tiny notch tiles ("2h"), and a fuller `medium` for the library.
enum RelativeTime {
    /// "now", "5m", "2h", "3d", "2w", then a short date for older items.
    /// Hand-rolled because RelativeDateTimeFormatter's "2 hr" is too wide for a
    /// 96pt notch tile.
    static func compact(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        switch s {
        case ..<45:        return "now"
        case ..<3600:      return "\(Int(s / 60))m"
        case ..<86_400:    return "\(Int(s / 3600))h"
        case ..<604_800:   return "\(Int(s / 86_400))d"
        case ..<2_419_200: return "\(Int(s / 604_800))w"
        default:           return shortDate.string(from: date)
        }
    }

    /// "Just now", "2 hours ago", … and a short date ("Jun 3") past ~6 days.
    static func medium(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 45 { return "Just now" }
        if s < 604_800 { return relative.localizedString(for: date, relativeTo: now) }
        return shortDate.string(from: date)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
