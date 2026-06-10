import Foundation
import PDFKit

/// Pulls the text layer out of a PDF (PDFKit, on-device) so saved PDFs are
/// searchable by their contents. Synchronous; callers offload it off the main
/// actor. Returns nil for image-only PDFs (no text layer) or non-PDFs.
enum PDFTextExtractor {
    private static let maxCharacters = 8_000

    static func extractText(from url: URL) -> String? {
        guard let doc = PDFDocument(url: url),
              let text = doc.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return String(text.prefix(maxCharacters))
    }
}
