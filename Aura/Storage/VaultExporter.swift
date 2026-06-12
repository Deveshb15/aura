import Foundation
import GRDB

/// Exports the entire vault to a self-contained folder where every saved item is
/// one human-readable file, then zips that folder so it can be saved anywhere.
///
/// Layout (only non-empty subfolders are created):
/// ```
/// Aura Export 2026-06-12/
///   Text/    0001 First line.txt
///   Links/   0002 host — title.txt
///   Images/  0003 screenshot.png      (original bytes)
///   Files/   0004 report.pdf          (original file, original name)
///   Colors/  0005 #FF5733.txt
///   aura-export.json                  (metadata manifest for every item)
/// ```
/// Originals are copied straight from `Assets/`; text/links/colors are written
/// as `.txt`. Each filename is prefixed with a zero-padded capture-order index,
/// which also guarantees uniqueness.
struct VaultExporter {
    let dbPool: DatabasePool
    let assetStore: AssetStore

    enum ExportError: LocalizedError {
        case noItems
        case zipFailed

        var errorDescription: String? {
            switch self {
            case .noItems: return "There are no saved items to export."
            case .zipFailed: return "Aura couldn't create the export archive."
            }
        }
    }

    /// Reads the whole vault, writes the export tree to a temp directory, zips it,
    /// and returns the URL of the temporary `.zip`. The caller is responsible for
    /// moving that zip to its final destination (the temp tree is cleaned up here).
    func export() async throws -> URL {
        // Chronological order so 0001 is the oldest capture — natural to read.
        let items = try await dbPool.read { db in
            try Item.order(Column("createdAt")).fetchAll(db)
        }
        guard !items.isEmpty else { throw ExportError.noItems }

        let collections = (try? await dbPool.read { db in try ItemCollection.fetchAll(db) }) ?? []
        let collectionNames = Dictionary(collections.map { ($0.id, $0.name) },
                                         uniquingKeysWith: { first, _ in first })
        let assetBase = assetStore.baseURL
        let folderName = "Aura Export \(Self.dateStamp())"

        // File I/O and zipping are synchronous and potentially large, so run them
        // off the main actor. Everything passed in is Sendable (value types + URL).
        return try await Task.detached(priority: .userInitiated) {
            try Self.writeTreeAndZip(items: items,
                                     collectionNames: collectionNames,
                                     assetBase: assetBase,
                                     folderName: folderName)
        }.value
    }

    // MARK: - Tree building (off main actor; pure file I/O)

    private static func writeTreeAndZip(items: [Item],
                                        collectionNames: [String: String],
                                        assetBase: URL,
                                        folderName: String) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("AuraExport-\(UUID().uuidString)", isDirectory: true)
        let root = work.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let width = max(4, String(items.count).count)
        var manifest: [ManifestEntry] = []
        manifest.reserveCapacity(items.count)

        for (offset, item) in items.enumerated() {
            let index = String(format: "%0\(width)d", offset + 1)
            let (subfolder, relativePath) = try writeItemFile(item,
                                                              index: index,
                                                              assetBase: assetBase,
                                                              root: root,
                                                              fm: fm)
            _ = subfolder
            manifest.append(ManifestEntry(item: item,
                                          file: relativePath,
                                          collection: item.collectionId.flatMap { collectionNames[$0] }))
        }

        // Metadata manifest — keeps the item files clean while preserving the
        // provenance (source app, exact dates, original URL, collection).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: root.appendingPathComponent("aura-export.json"), options: .atomic)

        return try zipDirectory(at: root, fm: fm)
    }

    /// Writes a single item to its type subfolder. Returns (subfolder, relative
    /// path within the export root) for the manifest.
    private static func writeItemFile(_ item: Item,
                                      index: String,
                                      assetBase: URL,
                                      root: URL,
                                      fm: FileManager) throws -> (String, String) {
        let subfolder: String
        let fileName: String
        var bytesToWrite: Data?
        var sourceToCopy: URL?

        switch item.itemType {
        case .text:
            subfolder = "Text"
            let base = sanitize(item.textContent ?? item.title ?? "", fallback: "Note")
            fileName = "\(index) \(base).txt"
            bytesToWrite = Data((item.textContent ?? item.title ?? "").utf8)

        case .url:
            subfolder = "Links"
            let label = linkLabel(for: item)
            fileName = "\(index) \(sanitize(label, fallback: "Link")).txt"
            bytesToWrite = Data(linkFileBody(for: item).utf8)

        case .color:
            subfolder = "Colors"
            let hex = item.colorHex ?? item.textContent ?? "color"
            fileName = "\(index) \(sanitize(hex, fallback: "Color")).txt"
            bytesToWrite = Data(hex.utf8)

        case .image:
            subfolder = "Images"
            if let path = item.assetPath {
                let src = assetBase.appendingPathComponent(path)
                let ext = src.pathExtension.isEmpty ? "png" : src.pathExtension
                let base = sanitize(strip(ext: ext, from: item.title ?? "Image"), fallback: "Image")
                fileName = "\(index) \(base).\(ext)"
                if fm.fileExists(atPath: src.path) { sourceToCopy = src }
            } else {
                let base = sanitize(item.title ?? "Image", fallback: "Image")
                fileName = "\(index) \(base).txt"
                bytesToWrite = Data("(original image unavailable)".utf8)
            }

        case .file:
            subfolder = "Files"
            let original = item.fileName ?? item.assetPath.map { ($0 as NSString).lastPathComponent } ?? "file"
            fileName = "\(index) \(sanitize(original, fallback: "File"))"
            if let path = item.assetPath {
                let src = assetBase.appendingPathComponent(path)
                if fm.fileExists(atPath: src.path) { sourceToCopy = src }
            }
            if sourceToCopy == nil { bytesToWrite = Data("(original file unavailable)".utf8) }
        }

        let dir = root.appendingPathComponent(subfolder, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(fileName)

        if let src = sourceToCopy {
            try fm.copyItem(at: src, to: dest)
        } else if let data = bytesToWrite {
            try data.write(to: dest, options: .atomic)
        }
        return (subfolder, "\(subfolder)/\(fileName)")
    }

    // MARK: - Zip (native, no dependency)

    /// Zips a directory using `NSFileCoordinator`'s `.forUploading` option, which
    /// produces a `<dirname>.zip` containing the folder. The system's archive is
    /// only valid inside the coordination block, so it's copied out immediately.
    private static func zipDirectory(at sourceDir: URL, fm: FileManager) throws -> URL {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var resultURL: URL?
        var copyError: Error?

        coordinator.coordinate(readingItemAt: sourceDir, options: [.forUploading], error: &coordError) { zipped in
            let dest = fm.temporaryDirectory
                .appendingPathComponent("AuraExport-\(UUID().uuidString)")
                .appendingPathExtension("zip")
            do {
                try fm.copyItem(at: zipped, to: dest)
                resultURL = dest
            } catch {
                copyError = error
            }
        }

        if let coordError { throw coordError }
        if let copyError { throw copyError }
        guard let resultURL else { throw ExportError.zipFailed }
        return resultURL
    }

    // MARK: - Helpers

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// A short, readable label for a link: "host — title" when both exist.
    private static func linkLabel(for item: Item) -> String {
        let host = item.host ?? item.linkURL?.host
        let title = (item.ogTitle ?? item.title).flatMap { $0 == host ? nil : $0 }
        switch (host, title) {
        case let (h?, t?): return "\(h) — \(t)"
        case let (h?, nil): return h
        case let (nil, t?): return t
        case (nil, nil): return item.textContent ?? item.linkURL?.absoluteString ?? "Link"
        }
    }

    /// The body written into a link's `.txt`: the URL first, then any title and
    /// description, so the file is useful opened on its own.
    private static func linkFileBody(for item: Item) -> String {
        var lines: [String] = [item.textContent ?? item.linkURL?.absoluteString ?? ""]
        if let title = item.ogTitle ?? item.title, !title.isEmpty {
            lines.append("")
            lines.append(title)
        }
        if let desc = item.ogDescription, !desc.isEmpty {
            lines.append("")
            lines.append(desc)
        }
        return lines.joined(separator: "\n")
    }

    /// Drops a redundant trailing extension from an image title (e.g. a title of
    /// "photo.jpg" becomes "photo" before we append the real extension).
    private static func strip(ext: String, from name: String) -> String {
        guard !ext.isEmpty, name.lowercased().hasSuffix("." + ext.lowercased()) else { return name }
        return String(name.dropLast(ext.count + 1))
    }

    /// Makes a string safe and tidy for a filename: strips path-illegal
    /// characters, collapses whitespace, and caps the length.
    private static func sanitize(_ raw: String, fallback: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        var cleaned = raw
            .components(separatedBy: .newlines).joined(separator: " ")
            .components(separatedBy: illegal).joined(separator: "-")
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { cleaned = fallback }
        return String(cleaned.prefix(60)).trimmingCharacters(in: .whitespaces)
    }
}

/// One row in `aura-export.json`. Mirrors the durable, user-meaningful columns of
/// an item plus the relative path of the exported file it corresponds to.
private struct ManifestEntry: Encodable {
    let file: String
    let type: String
    let title: String?
    let text: String?
    let url: String?
    let host: String?
    let sourceApp: String?
    let sourceURL: String?
    let collection: String?
    let fileName: String?
    let byteSize: Int?
    let createdAt: Date
    let updatedAt: Date

    init(item: Item, file: String, collection: String?) {
        self.file = file
        self.type = item.type
        self.title = item.title
        // Inline the payload for text-like items so the manifest is self-contained;
        // binary items reference their file instead.
        switch item.itemType {
        case .text, .color: self.text = item.textContent
        default: self.text = nil
        }
        self.url = item.linkURL?.absoluteString
        self.host = item.host
        self.sourceApp = item.sourceApp
        self.sourceURL = item.sourceURL
        self.collection = collection
        self.fileName = item.fileName
        self.byteSize = item.byteSize
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
    }
}
