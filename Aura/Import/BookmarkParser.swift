import Foundation
import SwiftSoup
import os

/// One bookmark extracted from a browser's exported "Netscape Bookmark File"
/// (the `.html` every browser produces). Folder structure is intentionally not
/// captured — import is flat.
struct ParsedBookmark {
    var url: URL
    var title: String        // anchor text, entity-decoded; falls back to host
    var addDate: Date?       // from ADD_DATE; nil when missing/implausible
    var iconData: Data?      // decoded from ICON="data:image/...;base64,..." only
}

/// Parses the Netscape Bookmark File format. The format leaves `<DT>`/`<DD>`/`<p>`
/// unclosed and nests `<DL>` for folders, which an HTML5 parser reparents
/// unpredictably — so we never rely on nesting. Every bookmark is an `<A HREF>`,
/// so we collect anchors in document order and ignore structure entirely.
///
/// Pure and synchronous (like `ArticleExtractor`); call it off the main actor.
enum BookmarkParser {
    private static let log = Logger(subsystem: "app.captureaura", category: "bookmark-import")

    /// All `<a href>` anchors, in document order, that parse into a URL. Scheme
    /// filtering (http/https only) is the importer's job — here we keep anything
    /// URL-constructible so the importer can count what it rejects.
    static func parse(html: String) -> [ParsedBookmark] {
        let anchors: [Element]
        do {
            let doc = try SwiftSoup.parse(html)
            anchors = try doc.select("a[href]").array()
        } catch {
            log.error("bookmark parse failed: \(error.localizedDescription)")
            return []
        }

        var results: [ParsedBookmark] = []
        results.reserveCapacity(anchors.count)
        for a in anchors {
            guard let bookmark = parseAnchor(a) else { continue }
            results.append(bookmark)
        }
        return results
    }

    private static func parseAnchor(_ a: Element) -> ParsedBookmark? {
        // `attr` is case-insensitive, so ADD_DATE/HREF/ICON all resolve.
        guard let href = try? a.attr("href"),
              let url = makeURL(from: href) else { return nil }

        let rawTitle = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var title = rawTitle.isEmpty ? (displayHost(url) ?? url.absoluteString) : rawTitle
        if title.count > 300 { title = String(title.prefix(300)) }

        let addDate = (try? a.attr("add_date")).flatMap(parseDate)
        let iconData = (try? a.attr("icon")).flatMap(decodeDataURIImage)

        return ParsedBookmark(url: url, title: title, addDate: addDate, iconData: iconData)
    }

    // MARK: - Helpers

    /// Lenient URL construction with a single percent-encoding retry so a valid
    /// but unescaped href (raw spaces in a path/query) isn't dropped.
    private static func makeURL(from href: String) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed) { return url }
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded) { return url }
        return nil
    }

    private static func displayHost(_ url: URL) -> String? {
        guard var host = url.host else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }

    /// ADD_DATE/LAST_MODIFIED units vary across browsers and edited files.
    /// Detect by magnitude, then sanity-clamp so one garbage row can't dominate
    /// the library's `createdAt DESC` sort.
    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let value = Int64(trimmed), value > 0 else { return nil }

        let seconds: Double
        switch trimmed.count {
        case 17...:  seconds = Double(value) / 1_000_000 - 11_644_473_600  // WebKit µs since 1601
        case 16:     seconds = Double(value) / 1_000_000                   // Unix µs
        case 13...15: seconds = Double(value) / 1_000                      // Unix ms
        default:     seconds = Double(value)                              // Unix s (the normal case)
        }

        let date = Date(timeIntervalSince1970: seconds)
        let lower = Date(timeIntervalSince1970: 946_684_800)               // 2000-01-01
        let upper = Date().addingTimeInterval(24 * 3600)                   // now + 24h skew
        guard date >= lower, date <= upper else { return nil }
        return date
    }

    /// Decodes an embedded `ICON="data:image/...;base64,..."` favicon offline.
    /// Remote `ICON_URI` values are ignored — enrichment fetches those. Caps the
    /// payload so thousands of large embedded icons can't blow up memory; final
    /// validation (real image bytes) is the importer's ImageIO check.
    private static func decodeDataURIImage(_ raw: String) -> Data? {
        guard raw.hasPrefix("data:image/"),
              let marker = raw.range(of: ";base64,") else { return nil }
        let base64 = String(raw[marker.upperBound...])
        guard base64.count < 700_000 else { return nil }   // ~512 KB decoded
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }
}
