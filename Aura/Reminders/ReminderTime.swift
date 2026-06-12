import Foundation

/// Formats a reminder's future (or recently past) fire time for the card chip:
/// "Today 3:00 PM", "Tomorrow 9:00 AM", "Fri 2:00 PM", "Jun 20, 3:00 PM".
enum ReminderTime {
    static func chipLabel(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let time = timeFormatter.string(from: date)
        if cal.isDateInToday(date)     { return "Today \(time)" }
        if cal.isDateInTomorrow(date)  { return "Tomorrow \(time)" }
        if cal.isDateInYesterday(date) { return "Yesterday \(time)" }
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: now),
                                      to: cal.startOfDay(for: date)).day ?? 0
        if days > 0 && days < 7 { return "\(weekdayFormatter.string(from: date)) \(time)" }
        return "\(dateFormatter.string(from: date)), \(time)"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
}
