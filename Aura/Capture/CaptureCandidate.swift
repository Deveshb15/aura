import Foundation

/// A pre-save capture: what we read off the clipboard or a drag, before it is
/// persisted. Both the nudge "keep" and the drop handler produce these and feed
/// them to `DataStore.save`.
struct CaptureCandidate {
    enum Payload {
        case text(String)
        case url(URL)
        case image(Data)
        case file(URL)
        case color(String)
    }

    var payload: Payload
    var sourceApp: String?
    var sourceURL: String?

    init(payload: Payload, sourceApp: String? = nil, sourceURL: String? = nil) {
        self.payload = payload
        self.sourceApp = sourceApp
        self.sourceURL = sourceURL
    }

    /// Classifies a raw string as a web URL, a hex color, or plain text.
    static func fromString(_ string: String, sourceApp: String? = nil, sourceURL: String? = nil) -> CaptureCandidate {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hex = ColorDetector.hexColor(in: trimmed) {
            return CaptureCandidate(payload: .color(hex), sourceApp: sourceApp, sourceURL: sourceURL)
        }
        if let url = Self.webURL(from: trimmed) {
            return CaptureCandidate(payload: .url(url), sourceApp: sourceApp, sourceURL: sourceURL)
        }
        return CaptureCandidate(payload: .text(string), sourceApp: sourceApp, sourceURL: sourceURL)
    }

    static func webURL(from string: String) -> URL? {
        guard !string.contains(" "), !string.contains("\n") else { return nil }
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }
}
