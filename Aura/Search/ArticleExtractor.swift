import Foundation
import SwiftSoup
import os

/// A lightweight "readability": pull the readable body text out of a page's
/// HTML with SwiftSoup so a saved link is searchable by what it's actually
/// about, not just its title. Drops non-content nodes, prefers the largest
/// likely content container, and falls back to the whole `<body>`.
///
/// Synchronous and pure; run it off the main actor (it's only ever called from
/// `LinkMetadataService.fetchArticleText`, a non-isolated async function).
enum ArticleExtractor {
    private static let log = Logger(subsystem: "app.captureaura", category: "article")
    private static let maxCharacters = 8_000

    static func extractText(fromHTML html: String, url: URL) -> String? {
        do {
            let doc = try SwiftSoup.parse(html, url.absoluteString)
            // Remove obvious non-content nodes before measuring text.
            try doc.select("script, style, noscript, nav, header, footer, aside, form, svg, iframe, button")
                .remove()

            // Prefer a recognizable content container; pick the text-richest one.
            let selectors = ["article", "main", "[role=main]", "#content", ".post",
                             ".article", ".entry-content", ".post-content"]
            var candidates: [Element] = []
            for selector in selectors {
                candidates.append(contentsOf: try doc.select(selector).array())
            }
            let container = candidates.max {
                ((try? $0.text().count) ?? 0) < ((try? $1.text().count) ?? 0)
            } ?? doc.body()

            guard let container else { return nil }
            let text = try container.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 40 else { return nil }   // skip near-empty shells (JS apps, paywalls)
            return String(text.prefix(maxCharacters))
        } catch {
            log.error("article extraction failed: \(error.localizedDescription)")
            return nil
        }
    }
}
