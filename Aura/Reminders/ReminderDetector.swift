import Foundation

/// Unified reminder-detection entry point used by the composer and the notch.
/// Prefers the on-device AI (`ReminderIntelligence`) — robust at natural
/// language and relative times — and falls back to the keyword + NSDataDetector
/// heuristic (`ReminderParser`) when Apple Intelligence is unavailable.
enum ReminderDetector {
    static func detect(_ text: String, now: Date = Date()) async -> ReminderParse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        if ReminderIntelligence.isAvailable,
           let ai = await ReminderIntelligence.detect(in: trimmed, now: now) {
            return ai
        }
        return ReminderParser.parse(trimmed, now: now)
    }
}
