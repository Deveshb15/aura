import Foundation
import GRDB

/// One dense vector per item — the `embedding` table (added in migration v3).
/// The vector is stored as a packed little-endian Float32 BLOB; `model`/`dims`
/// let us detect a model change later and re-embed.
struct EmbeddingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "embedding"

    var itemId: String
    var vector: Data
    var model: String
    var dims: Int
    var sourceHash: String?
    var updatedAt: Date
}

extension EmbeddingRecord {
    init(itemId: String,
         vector: [Float],
         model: String,
         sourceHash: String?,
         updatedAt: Date = Date()) {
        self.itemId = itemId
        self.vector = Self.data(from: vector)
        self.model = model
        self.dims = vector.count
        self.sourceHash = sourceHash
        self.updatedAt = updatedAt
    }

    var floats: [Float] { Self.floats(from: vector) }

    /// Pack a vector into a Float32 BLOB (native byte order — read back on the
    /// same machine, so endianness is consistent).
    static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func floats(from data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.stride
        guard count > 0 else { return [] }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(count))
        }
    }
}
