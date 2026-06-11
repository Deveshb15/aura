import Foundation
import GRDB

/// Hybrid retrieval: blend FTS5 keyword matching (exact terms) with semantic
/// vector similarity (meaning), fused by Reciprocal Rank Fusion. Keyword search
/// nails literal queries ("github", a filename); vector search handles
/// conceptual ones ("that documentary about money", "everything on investing").
/// RRF needs no score calibration between the two — it ranks purely by each
/// item's position in each list, so the lists' incomparable score scales (BM25
/// rank vs cosine) never have to be reconciled.
struct HybridSearch {
    let dbPool: DatabasePool
    let semanticIndex: SemanticIndex
    var embeddingService: EmbeddingService = .shared

    /// RRF damping constant; 60 is the standard value from the original paper.
    private let rrfK = 60.0
    /// How many candidates to pull from each retriever before fusing.
    private let candidateLimit = 60

    /// Ranked items best-match-first. Empty/blank query returns `[]` (callers
    /// substitute the full library). Degrades to keyword-only when embeddings
    /// aren't ready yet (assets downloading) and to semantic-only when a query
    /// has no literal matches.
    func search(_ query: String) async -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        async let keyword = keywordIDs(trimmed)
        async let semantic = semanticIDs(trimmed)
        let keywordRanked = await keyword
        let semanticRanked = await semantic

        var fused: [String: Double] = [:]
        for (rank, id) in keywordRanked.enumerated() {
            fused[id, default: 0] += 1.0 / (rrfK + Double(rank + 1))
        }
        for (rank, id) in semanticRanked.enumerated() {
            fused[id, default: 0] += 1.0 / (rrfK + Double(rank + 1))
        }
        guard !fused.isEmpty else { return [] }

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
