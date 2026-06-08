import Foundation
import GRDB

/// A category / collection. Built-in tabs are seeded at migration time; users
/// can add their own in a later phase.
struct Collection: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "collection"

    var id: String
    var name: String
    var kind: String        // "builtin" | "user"
    var symbol: String?     // SF Symbol name
    var sortOrder: Int
    var createdAt: Date
}
