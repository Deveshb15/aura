import Foundation

/// Result of inspecting a note's text for reminder intent + a fire date.
/// Produced by the on-device AI (`ReminderIntelligence`) when available, or by
/// the heuristic `ReminderParser` fallback otherwise.
struct ReminderParse: Equatable {
    var isReminder: Bool       // text reads like "remind me …"
    var date: Date?            // first FUTURE fire time parsed, or nil
    var cleanedTitle: String?  // text with the "remind me to " prefix stripped, for display

    static let none = ReminderParse(isReminder: false, date: nil, cleanedTitle: nil)
}

/// Heuristic reminder detector: a keyword intent match plus `NSDataDetector`
/// date extraction. Used as the fallback when Apple Intelligence isn't
/// available (macOS < 26 / Intel / disabled). Pure and synchronous.
enum ReminderParser {

    /// Case-insensitive intent triggers.
    private static let intentPatterns = [
        "remind me", "reminder to", "reminder that", "reminder for",
        "don't let me forget", "dont let me forget", "remember to"
    ]

    static func parse(_ text: String, now: Date = Date()) -> ReminderParse {
        let lower = text.lowercased()
        let isReminder = intentPatterns.contains { lower.contains($0) }
        guard isReminder else { return .none }
        return ReminderParse(isReminder: true,
                             date: firstFutureDate(in: text, now: now),
                             cleanedTitle: cleanedTitle(from: text))
    }

    /// First `NSDataDetector` date match that is in the future relative to
    /// `now`. A time-only match already past today (e.g. "at 9am" at noon) is
    /// rolled forward one day.
    static func firstFutureDate(in text: String, now: Date = Date()) -> Date? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var candidates: [Date] = []
        for match in detector.matches(in: text, options: [], range: range) {
            guard let date = match.date else { continue }
            if date > now {
                candidates.append(date)
            } else if let rolled = Calendar.current.date(byAdding: .day, value: 1, to: date),
                      rolled > now {
                candidates.append(rolled)
            }
        }
        return candidates.min()
    }

    /// Sensible default when intent is present but no time parsed: tomorrow at
    /// 9:00 AM local. The composer pre-fills its picker with this so the user
    /// always has something to adjust.
    static func defaultFireDate(now: Date = Date()) -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// Strips a leading "remind me to " / "reminder to " so a note title reads
    /// naturally. Conservative — only known prefixes, never mangles the body.
    private static func cleanedTitle(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for prefix in ["remind me to ", "remind me that ", "remind me ",
                       "reminder to ", "reminder: ", "remember to "] {
            if lower.hasPrefix(prefix) {
                return String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return trimmed
    }
}
