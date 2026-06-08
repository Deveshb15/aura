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
    var itemType: ItemType { ItemType(rawValue: type) ?? .text }
    var subtype: URLSubtype { URLSubtype(rawValue: urlSubtype ?? "") ?? .generic }

    /// Whether a primary click can "open" this item (vs. just copy it).
    var canOpen: Bool {
        switch itemType {
        case .url: return URL(string: textContent ?? "") != nil
        case .file, .image: return assetPath != nil
        case .text, .color: return false
        }
    }

    /// Combined haystack for simple in-memory search (FTS5 used for the real search later).
    var searchText: String {
        [title, textContent, host, fileName, ogTitle, ogDescription]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
