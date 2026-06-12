import Foundation
import GRDB

/// Turns a browser's exported bookmarks (`.html`, Netscape format) into `url`
/// items. Stands alone like `VaultExporter` so `DataStore` stays a thin
/// coordinator; all the work here runs off the main actor.
struct BookmarkImporter {
    let dbPool: DatabasePool
    let assetStore: AssetStore

    struct ImportResult: Equatable {
        var imported: Int
        var skippedDuplicates: Int
        var skippedInvalid: Int

        /// Total bookmarks the parser recognized. Zero distinguishes a real but
        /// empty/foreign file ("not a bookmarks file") from one where every link
        /// was filtered or already present.
        var totalParsed: Int { imported + skippedDuplicates + skippedInvalid }
    }

    enum ImportError: LocalizedError {
        case unreadableFile
        case fileTooLarge

        var errorDescription: String? {
            switch self {
            case .unreadableFile: return "Couldn't read that file. Make sure it's a bookmarks HTML file exported from your browser."
            case .fileTooLarge:   return "That bookmarks file is too large to import."
            }
        }
    }

    private static let maxFileBytes = 100 * 1024 * 1024   // 100 MB
    private static let maxIconBytes = 256 * 1024          // 256 KB decoded
    private static let insertChunkSize = 500

    /// Parses, filters, dedupes, and inserts. Returns the result plus the new
    /// item IDs so the caller can drive throttled enrichment.
    func run(fileURL: URL) async throws -> (ImportResult, [String]) {
        let html = try readHTML(at: fileURL)
        let parsed = BookmarkParser.parse(html: html)

        // Existing vault URLs, normalized, so re-imports are idempotent.
        var seenKeys = try await existingURLKeys()

        var accepted: [(ParsedBookmark, URL)] = []
        var skippedDuplicates = 0
        var skippedInvalid = 0

        for bookmark in parsed {
            // http/https + host only. Reuses the same gate as clipboard capture,
            // which drops javascript:/place:/chrome:/about:/file:/data:/mailto:.
            guard let url = CaptureCandidate.webURL(from: bookmark.url.absoluteString) else {
                skippedInvalid += 1
                continue
            }

            let key = Self.normalizedKey(url)
            guard !seenKeys.contains(key) else {
                skippedDuplicates += 1
                continue
            }
            seenKeys.insert(key)

            accepted.append((bookmark, url))
        }

        // The user just imported these, so they should land at the TOP of the
        // library (which orders by createdAt desc). Stamp descending timestamps
        // anchored at the import moment, newest-bookmark first, so the whole batch
        // sits above existing captures with the most recently bookmarked on top.
        accepted.sort { ($0.0.addDate ?? .distantPast) > ($1.0.addDate ?? .distantPast) }
        let now = Date()
        var items: [Item] = []
        items.reserveCapacity(accepted.count)
        for (offset, pair) in accepted.enumerated() {
            let createdAt = now.addingTimeInterval(-Double(offset) * 0.001)
            items.append(buildItem(pair.0, url: pair.1, createdAt: createdAt))
        }

        let newIDs = items.map(\.id)
        try await insert(items)

        let result = ImportResult(imported: items.count,
                                  skippedDuplicates: skippedDuplicates,
                                  skippedInvalid: skippedInvalid)
        return (result, newIDs)
    }

    // MARK: - Steps

    private func readHTML(at fileURL: URL) throws -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs?[.size] as? Int) ?? 0
        guard size <= Self.maxFileBytes else { throw ImportError.fileTooLarge }

        guard let data = try? Data(contentsOf: fileURL) else { throw ImportError.unreadableFile }
        guard var html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadableFile
        }
        if html.hasPrefix("\u{FEFF}") { html.removeFirst() }   // strip BOM
        return html
    }

    private func existingURLKeys() async throws -> Set<String> {
        try await dbPool.read { db in
            let urls = try String.fetchAll(
                db,
                sql: "SELECT textContent FROM item WHERE type = ? AND textContent IS NOT NULL",
                arguments: [ItemType.url.rawValue])
            var set = Set<String>(minimumCapacity: urls.count)
            for raw in urls {
                if let url = URL(string: raw) { set.insert(Self.normalizedKey(url)) }
            }
            return set
        }
    }

    /// Mirrors the `.url` branch of `DataStore.save`, stamped with the import-time
    /// `createdAt` (so imports surface on top) and an offline-decoded favicon.
    private func buildItem(_ bookmark: ParsedBookmark, url: URL, createdAt: Date) -> Item {
        var item = Item(type: .url, createdAt: createdAt)
        item.textContent = url.absoluteString
        item.host = url.host
        item.title = bookmark.title
        item.urlSubtype = URLClassifier.subtype(for: url).rawValue
        item.sourceApp = "Bookmarks"

        if let icon = bookmark.iconData,
           icon.count <= Self.maxIconBytes,
           AssetStore.imageExtension(for: icon) != nil,                 // ImageIO trust boundary
           let stored = try? assetStore.storeImage(icon, subdir: "favicon") {
            item.faviconPath = stored.relativePath
        }
        return item
    }

    /// One transaction per chunk: a single giant transaction holds the write
    /// lock too long, and per-row transactions thrash the FTS5 sync triggers.
    private func insert(_ items: [Item]) async throws {
        guard !items.isEmpty else { return }
        var index = 0
        while index < items.count {
            let end = min(index + Self.insertChunkSize, items.count)
            let chunk = Array(items[index..<end])
            try await dbPool.write { db in
                for item in chunk { try item.insert(db) }
            }
            index = end
        }
    }

    // MARK: - URL normalization (dedup key only — stored URL is left untouched)

    /// A conservative key that collapses trivially-identical URLs (case, trailing
    /// slash, default port, throwaway fragment) without ever merging genuinely
    /// different ones: query strings, http-vs-https, and www are all preserved.
    static func normalizedKey(_ url: URL) -> String {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let scheme = (comps?.scheme ?? url.scheme ?? "").lowercased()
        let host = (comps?.host ?? url.host ?? "").lowercased()

        var hostPort = host
        if let port = comps?.port {
            let isDefault = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
            if !isDefault { hostPort += ":\(port)" }
        }

        var path = comps?.percentEncodedPath ?? url.path
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }

        var key = "\(scheme)://\(hostPort)\(path)"
        if let query = comps?.percentEncodedQuery, !query.isEmpty { key += "?\(query)" }
        // Keep only SPA-route fragments (#!/… or #/…); drop throwaway anchors.
        if let frag = comps?.percentEncodedFragment, frag.hasPrefix("/") || frag.hasPrefix("!") {
            key += "#\(frag)"
        }
        return key
    }
}
