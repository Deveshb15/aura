import Foundation
import GRDB

/// A single saved item. All capture types share this one table so the bento
/// query and full-text-search sync stay simple; type-specific columns are nil
/// when unused. Originals live on disk under Assets/; only a small thumbnail
/// blob (<100KB) is stored inline for fast grid rendering.
struct Item: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "item"

    var id: String                  // UUID string
    var type: String                // ItemType raw value
    var createdAt: Date
    var updatedAt: Date

    // Primary text payload: snippet text, URL string, or hex string.
    var textContent: String?
    var title: String?
    var urlSubtype: String?         // URLSubtype raw value

    // Provenance
    var sourceApp: String?
    var sourceURL: String?          // org.nspasteboard.source if present

    // On-disk asset (image / file), relative to the Assets/ base directory.
    var assetPath: String?
    var fileName: String?
    var uti: String?
    var byteSize: Int?

    // Cached thumbnail for fast grid render.
    var thumbnail: Data?
    var thumbWidth: Int?
    var thumbHeight: Int?

    // Open Graph cache (populated in a later phase; columns exist from v1).
    var ogTitle: String?
    var ogDescription: String?
    var ogImagePath: String?
    var faviconPath: String?
    var host: String?

    // Color cache.
    var colorHex: String?

    var collectionId: String?

    // Searchable text mined from the item's content (image OCR, link article
    // body, video description, PDF text). Feeds both the FTS5 index and the
    // semantic embedding. Populated asynchronously after save (v3 column).
    var extractedText: String?

    init(id: String = UUID().uuidString,
         type: ItemType,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.type = type.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Item {
    /// Columns fetched for the live library / notch observation — every column
    /// the UI renders, but NOT the heavy `extractedText` (image OCR, article
    /// bodies, document text). Search reads that straight from the DB
    /// (`HybridSearch`) and the grid never displays it, so carrying it in the
    /// 400-row reactive array — re-deserialized on every write — was pure waste.
    /// Omitted from the selection, `extractedText` decodes back to nil, which the
    /// display path is fine with. Keep in sync with the stored properties above.
    static let liveColumns: [Column] = [
        Column("id"), Column("type"), Column("createdAt"), Column("updatedAt"),
        Column("textContent"), Column("title"), Column("urlSubtype"),
        Column("sourceApp"), Column("sourceURL"), Column("assetPath"),
        Column("fileName"), Column("uti"), Column("byteSize"),
        Column("thumbnail"), Column("thumbWidth"), Column("thumbHeight"),
        Column("ogTitle"), Column("ogDescription"), Column("ogImagePath"),
        Column("faviconPath"), Column("host"), Column("colorHex"),
        Column("collectionId"),
    ]

    var itemType: ItemType { ItemType(rawValue: type) ?? .text }
    var subtype: URLSubtype { URLSubtype(rawValue: urlSubtype ?? "") ?? .generic }

    /// The URL this item points at: the whole content for `.url` items, or the
    /// first web URL embedded in a `.text` capture ("link + note" messages).
    var linkURL: URL? {
        switch itemType {
        case .url: return URL(string: textContent ?? "")
        case .text: return CaptureCandidate.firstWebURL(in: textContent ?? "")
        default: return nil
        }
    }

    /// Source-app markers stamped on notes written inside Carpet — the Library
    /// composer (`"Carpet"`) and the notch quick-note composer
    /// (`"Carpet Quick Note"`). Used to route them to the Notes category.
    static let noteSourceApps: Set<String> = ["Carpet", "Carpet Quick Note"]

    /// A text note authored inside Carpet, as opposed to text captured from the
    /// clipboard. These are the items that belong to the Notes category.
    var isCarpetNote: Bool {
        itemType == .text && (sourceApp.map(Item.noteSourceApps.contains) ?? false)
    }

    /// Whether a primary click can "open" this item (vs. just copy it).
    var canOpen: Bool {
        switch itemType {
        case .url, .text: return linkURL != nil
        case .file, .image: return assetPath != nil
        case .color: return false
        }
    }

    /// Combined haystack mined from every text-bearing field. Used as the
    /// in-memory filter fallback, and — crucially — as the corpus we both feed
    /// to FTS5 and embed, so keyword and semantic search see the same text.
    var searchText: String {
        [title, textContent, host, fileName, ogTitle, ogDescription, extractedText]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
