import Foundation
import GRDB

/// A category / collection (named `ItemCollection` to avoid colliding with the
/// standard library's `Collection` protocol). Built-in starter collections are
/// seeded at migration time; users manage their own.
struct ItemCollection: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "collection"

    var id: String
    var name: String
    var kind: String        // "builtin" | "user"
    var symbol: String?     // SF Symbol name
    var sortOrder: Int
    var createdAt: Date
}
