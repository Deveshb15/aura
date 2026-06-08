import Foundation

/// Detects a hex color in copied text so it can be shown as a swatch.
enum ColorDetector {
    /// Returns a normalized "#RRGGBB" / "#RRGGBBAA" string if the input *is*
    /// essentially a single hex color, else nil. Intentionally strict so we
    /// don't turn arbitrary text into color cards.
    static func hexColor(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 9 else { return nil }
        let body = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let valid = body.allSatisfy { $0.isHexDigit }
        guard valid, [3, 6, 8].contains(body.count) else { return nil }
        return "#" + body.uppercased()
    }
}
