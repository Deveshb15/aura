import Foundation
import GRDB
import Accelerate

/// In-memory mirror of every item's embedding vector plus brute-force cosine
/// ranking. At a few thousand items this is sub-10 ms per query, so no ANN
/// index is needed (revisit at ~100k items → sqlite-vec). Vectors are stored
/// pre-normalized, so cosine similarity is a single `cblas_sdot`.
actor SemanticIndex {
    private let dbPool: DatabasePool
    private var vectors: [(itemId: String, vector: [Float])] = []
    private var loaded = false

    /// Upper bound on vectors held in RAM. At 512 dims × 4 B ≈ 2 KB each, this
    /// caps the index at ~40 MB instead of growing unbounded with the vault
    /// (~100 MB at 50 k items, more beyond). The most-recent items stay
    /// semantically searchable; older ones remain findable via FTS5 keyword
    /// search, which `HybridSearch` already fuses in.
    // TODO: swap to sqlite-vec (ANN) to make the whole vault semantic again
    // without holding every vector in memory — the `embedding` table is already
    // isolated for exactly this.
    private static let maxVectors = 20_000

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    /// Load (or fully reload) the most-recent vectors into memory (capped).
    func reload() async {
        let records: [EmbeddingRecord] = (try? await dbPool.read { db in
            try EmbeddingRecord
                .order(Column("updatedAt").desc)
                .limit(Self.maxVectors)
                .fetchAll(db)
        }) ?? []
        vectors = records.map { ($0.itemId, $0.floats) }
        loaded = true
    }

    /// Insert/replace one item's vector so a freshly-captured item is
    /// searchable immediately, without a full reload.
    func upsert(itemId: String, vector: [Float]) {
        if let i = vectors.firstIndex(where: { $0.itemId == itemId }) {
            vectors[i].vector = vector
        } else {
            vectors.append((itemId, vector))
        }
        loaded = true
    }

    func remove(itemId: String) {
        vectors.removeAll { $0.itemId == itemId }
    }

    /// Item ids ranked by descending cosine similarity to `query` (which must
    /// already be L2-normalized), paired with their score, capped at `limit`.
    func rank(query: [Float], limit: Int) async -> [(itemId: String, score: Float)] {
        if !loaded { await reload() }
        guard !query.isEmpty else { return [] }
        let dim = Int32(query.count)

        var scored: [(itemId: String, score: Float)] = []
        scored.reserveCapacity(vectors.count)
        for entry in vectors where entry.vector.count == query.count {
            let score = query.withUnsafeBufferPointer { q in
                entry.vector.withUnsafeBufferPointer { v in
                    cblas_sdot(dim, q.baseAddress, 1, v.baseAddress, 1)
                }
            }
            scored.append((entry.itemId, score))
        }
        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(limit))
    }
}
