import Foundation
import GRDB

/// Keyword-authoritative retrieval: FTS5 keyword/prefix matching (exact terms)
/// defines the result set, and semantic vector similarity only re-orders those
/// matches via Reciprocal Rank Fusion. Keyword search nails literal queries
/// ("github", a filename); semantic re-ranking floats the most meaning-relevant
/// of the keyword hits to the top. Semantic results are deliberately NOT allowed
/// to introduce items on their own: the on-device embedding model's cosine
/// similarities are anisotropic (unrelated text scores as high as related text),
/// so a semantic-only fallback would surface irrelevant notes for any query.
/// RRF needs no score calibration between the two — it ranks purely by each
/// item's position in each list, so the incomparable score scales (BM25 rank vs
/// cosine) never have to be reconciled.
struct HybridSearch {
    let dbPool: DatabasePool
    let semanticIndex: SemanticIndex
    var embeddingService: EmbeddingService = .shared

    /// RRF damping constant; 60 is the standard value from the original paper.
    private let rrfK = 60.0
    /// How many candidates to pull from each retriever before fusing.
    private let candidateLimit = 60

    /// Ranked items best-match-first, restricted to keyword/prefix matches.
    /// Empty/blank query, or a query with no literal match, returns `[]` (the
    /// caller shows the empty state). Semantic re-ranking is skipped gracefully
    /// when embeddings aren't ready yet (assets downloading), leaving plain BM25
    /// keyword order.
    func search(_ query: String) async -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Keyword (FTS) is authoritative — it defines the result set. A query
        // with no literal/prefix match returns nothing (the caller shows the
        // empty state) rather than falling back to semantic nearest-neighbors:
        // with the on-device embedding model those similarities are anisotropic
        // (unrelated notes score as high as relevant ones), so a fallback only
        // surfaces junk.
        let keywordRanked = await keywordIDs(trimmed)
        guard !keywordRanked.isEmpty else { return [] }
        let keywordSet = Set(keywordRanked)

        // Semantic similarity only re-orders the keyword matches; it never
        // introduces an item the keyword search didn't already find.
        let semanticRanked = await semanticIDs(trimmed)

        var fused: [String: Double] = [:]
        for (rank, id) in keywordRanked.enumerated() {
            fused[id, default: 0] += 1.0 / (rrfK + Double(rank + 1))
        }
        for (rank, id) in semanticRanked.enumerated() where keywordSet.contains(id) {
            fused[id, default: 0] += 1.0 / (rrfK + Double(rank + 1))
        }

        let orderedIDs = fused.sorted { $0.value > $1.value }.map(\.key)
        return await items(for: orderedIDs)
    }

    // MARK: - Retrievers

    /// FTS5 prefix match → item ids in BM25 rank order. Distils the query to its
    /// content terms first (drops stopwords/instruction filler), then tries
    /// AND-of-prefixes for precision and falls back to OR-of-prefixes for recall
    /// — so a long conversational query still matches on its few real terms
    /// instead of requiring every filler word ("someone/show/it/to/me").
    private func keywordIDs(_ query: String) async -> [String] {
        let terms = QueryDistiller.contentTerms(query)
        let patterns: [FTS5Pattern] = [
            QueryDistiller.prefixPattern(terms, joinWithOR: false),
            QueryDistiller.prefixPattern(terms, joinWithOR: true),
            FTS5Pattern(matchingAllPrefixesIn: query),   // last-resort fallback
        ].compactMap { $0 }

        for pattern in patterns {
            let ids = await match(pattern)
            if !ids.isEmpty { return ids }
        }
        return []
    }

    private func match(_ pattern: FTS5Pattern) async -> [String] {
        (try? await dbPool.read { [candidateLimit] db -> [String] in
            try String.fetchAll(db, sql: """
                SELECT item.id FROM item
                JOIN item_fts ON item_fts.rowid = item.rowid
                WHERE item_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """, arguments: [pattern, candidateLimit])
        }) ?? []
    }

    /// Embed the query → cosine rank over the in-memory vector cache → item ids.
    /// Embeds the distilled content terms so the mean-pooled vector concentrates
    /// on the topic rather than conversational filler.
    private func semanticIDs(_ query: String) async -> [String] {
        guard let vector = await embeddingService.embed(QueryDistiller.embeddingText(query)) else { return [] }
        let ranked = await semanticIndex.rank(query: vector, limit: candidateLimit)
        return ranked.map(\.itemId)
    }

    // MARK: - Hydration

    /// Fetch the items for the fused ids, preserving the fused order.
    private func items(for ids: [String]) async -> [Item] {
        guard !ids.isEmpty else { return [] }
        let byID: [String: Item] = (try? await dbPool.read { db in
            try Item.filter(keys: ids).fetchAll(db)
        })?.reduce(into: [:]) { $0[$1.id] = $1 } ?? [:]
        return ids.compactMap { byID[$0] }
    }
}
