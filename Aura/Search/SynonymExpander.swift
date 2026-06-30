import Foundation
import NaturalLanguage
import os

/// Query-side synonym expansion using Apple's on-device **static word embedding**
/// (`NLEmbedding.wordEmbedding`, macOS 10.15+, built into the OS — no bundled
/// asset and no download). Given a query term it returns nearby words — "hike" →
/// trek, walk, climb — which the keyword retriever ORs into its FTS prefix
/// pattern, so a note that only says "trek" is still found by a search for "hike".
///
/// This is deliberately NOT the anisotropic *sentence* model used for semantic
/// re-ranking (`EmbeddingService`). It is a word-level neighbour lookup used only
/// to widen the keyword query — FTS keyword matching stays authoritative and we
/// never do cosine matching over documents.
///
/// An `actor` so the embedding loads once and is accessed serially off the main
/// thread; a lookup is sub-millisecond.
actor SynonymExpander {
    static let shared = SynonymExpander()

    private let log = Logger(subsystem: "app.captureaura", category: "synonyms")
    private var embedding: NLEmbedding?
    private var attemptedLoad = false

    // MARK: - Tunables (precision vs recall)

    /// How many raw neighbours to ask the model for. We over-fetch because most
    /// of the closest neighbours are inflections of the same stem (already
    /// covered by FTS prefix matching) which we then drop.
    private let neighborLookupCount = 12
    /// Cap on distinct cross-stem synonyms kept per term.
    private let maxSynonymsPerTerm = 6
    /// Cosine distance ceiling (0 = identical, 2 = opposite). Neighbours come back
    /// ascending, so once we pass this we can stop enumerating.
    private let maxNeighborDistance: NLDistance = 1.0
    /// Don't expand 1–2 char tokens — their neighbours are noisy.
    private let minTermLength = 3
    /// Only expand the first few content terms; a long query is already specific.
    private let maxTermsToExpand = 3

    /// Up to `maxSynonymsPerTerm` nearby words for `term`: lowercased, alphanumeric,
    /// excluding the term itself, stopwords, and any neighbour that's just a prefix
    /// variant of the term (e.g. "hiking" for "hike" — already matched by `"hike"*`).
    func neighbors(for term: String) -> [String] {
        guard let model = load() else { return [] }
        var out: [String] = []
        model.enumerateNeighbors(for: term,
                                 maximumCount: neighborLookupCount,
                                 distanceType: .cosine) { word, distance in
            // Ascending distance → once past the ceiling, nothing better follows.
            guard distance <= maxNeighborDistance else { return false }
            let w = word.lowercased()
            let isAlnum = w.allSatisfy { $0.isLetter || $0.isNumber }
            if isAlnum, w != term, !w.hasPrefix(term), !term.hasPrefix(w),
               !QueryDistiller.isStopword(w) {
                out.append(w)
                if out.count >= maxSynonymsPerTerm { return false }
            }
            return true
        }
        return out
    }

    /// The original terms **plus** their deduped synonyms. Order-stable; original
    /// terms always come first so the caller can keep them weighted. Only the
    /// first `maxTermsToExpand` long-enough terms are expanded — a long query is
    /// already specific.
    func expand(_ terms: [String]) -> [String] {
        guard !terms.isEmpty else { return [] }
        var result = terms
        var seen = Set(terms)
        for synonym in synonyms(for: terms) where seen.insert(synonym).inserted {
            result.append(synonym)
        }
        return result
    }

    /// Synonyms only (no originals) for the first `maxTerms` expandable terms
    /// (defaults to the query-path cap; index-time tagging passes a higher one to
    /// expand more of an item's seed terms).
    func synonyms(for terms: [String], maxTerms: Int? = nil) -> [String] {
        let expandable = terms.filter { $0.count >= minTermLength }.prefix(maxTerms ?? maxTermsToExpand)
        var out: [String] = []
        var seen = Set(terms.map { $0.lowercased() })
        for term in expandable {
            for synonym in neighbors(for: term) where seen.insert(synonym).inserted {
                out.append(synonym)
            }
        }
        return out
    }

    // MARK: - Model lifecycle

    /// Loads the English word embedding once. Returns nil (a graceful no-op for
    /// all callers) if the OS has no word-embedding asset for English.
    private func load() -> NLEmbedding? {
        if attemptedLoad { return embedding }
        attemptedLoad = true
        embedding = NLEmbedding.wordEmbedding(for: .english)
        if embedding == nil {
            log.error("NLEmbedding word embedding unavailable for English — synonym expansion disabled")
        }
        return embedding
    }
}
