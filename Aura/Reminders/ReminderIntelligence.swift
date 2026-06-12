import Foundation
import FoundationModels

/// On-device reminder detection via Apple's Foundation Models (the same engine
/// behind `AnswerService`). Decides whether a note is a reminder and resolves
/// its natural-language time ("tomorrow at 3pm", "in 2 hours", "next Friday")
/// into an absolute local date. Everything that touches `FoundationModels`
/// lives behind an availability check, so the macOS 14 build links and runs on
/// older / Intel Macs — they just fall back to the heuristic `ReminderParser`.
enum ReminderIntelligence {

    /// Whether the on-device model can be used right now (macOS 26+, Apple
    /// Silicon, Apple Intelligence enabled and downloaded).
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    /// Classifies `text` and extracts a fire date. Returns `nil` when the model
    /// is unavailable or errors, so the caller can fall back to the heuristic.
    static func detect(in text: String, now: Date = Date()) async -> ReminderParse? {
        guard #available(macOS 26.0, *), isAvailable else { return nil }
        return await Extractor.detect(in: text, now: now)
    }
}

@available(macOS 26.0, *)
private enum Extractor {

    @Generable
    struct ReminderExtraction {
        @Guide(description: "true only if the note is asking to be reminded to do something at a specific time or date")
        var isReminder: Bool
        @Guide(description: "The reminder fire time as yyyy-MM-dd'T'HH:mm in the user's local time, in the future. Empty string if the note implies no time or date.")
        var isoDateTime: String
        @Guide(description: "A short imperative title for the reminder without the words 'remind me', for example 'Call mom'")
        var title: String
    }

    static func detect(in text: String, now: Date) async -> ReminderParse? {
        let instructions = """
        You decide whether a short personal note is a reminder, and if so, when it should fire.
        The user's current local date and time is \(format(now)) (format yyyy-MM-dd'T'HH:mm).
        Resolve relative expressions ("tomorrow", "tonight", "in 2 hours", "next Friday", \
        "this weekend", "in 20 minutes") into an absolute LOCAL date-time strictly in the \
        future relative to now. If the note expresses a reminder but states no time, set \
        isReminder true and leave isoDateTime empty. If it is not a reminder, set isReminder \
        false. Never invent a time that wasn't implied.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: text, generating: ReminderExtraction.self)
            let result = response.content
            guard result.isReminder else { return .none }
            let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return ReminderParse(isReminder: true,
                                 date: parse(result.isoDateTime, now: now),
                                 cleanedTitle: title.isEmpty ? nil : title)
        } catch {
            return nil   // fall back to the heuristic parser
        }
    }

    /// Parses the model's `yyyy-MM-dd'T'HH:mm` (or `…:ss`) output into a Date in
    /// the local timezone. Only accepts a result in the future.
    static func parse(_ iso: String, now: Date) -> Date? {
        let trimmed = iso.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for fmt in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = fmt
            if let date = formatter.date(from: trimmed) {
                return date > now ? date : nil
            }
        }
        return nil
    }

    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.string(from: date)
    }
}
