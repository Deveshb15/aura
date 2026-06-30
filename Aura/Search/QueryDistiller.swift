import Foundation
import GRDB

/// Turns a conversational query ("someone is building consumer product -- show
/// it to me") into its content terms ("building consumer product") so both
/// retrievers focus on meaning, not filler. Without this, FTS5's all-tokens AND
/// matches nothing on a long query and the mean-pooled embedding gets dragged
/// off-topic by stopwords.
enum QueryDistiller {

    /// Content terms in original order, lowercased, de-duplicated. Drops
    /// stopwords + sub-2-char tokens. If everything is stripped (an all-stopword
    /// query), returns the raw alphanumeric tokens so search is never empty.
    static func contentTerms(_ query: String) -> [String] {
        let raw = tokenize(query)
        let kept = raw.filter { $0.count >= 2 && !stopwords.contains($0) }
        let terms = kept.isEmpty ? raw : kept
        var seen = Set<String>()
        return terms.filter { seen.insert($0).inserted }
    }

    /// Distilled terms rejoined for embedding (or the trimmed query if empty).
    static func embeddingText(_ query: String) -> String {
        let terms = contentTerms(query)
        return terms.isEmpty ? query.trimmingCharacters(in: .whitespacesAndNewlines)
                             : terms.joined(separator: " ")
    }

    /// A prefix FTS5 pattern over the terms: `"a"* "b"*` (AND) or
    /// `"a"* OR "b"*` (OR). Tokens are alphanumeric, so the raw pattern is safe.
    static func prefixPattern(_ terms: [String], joinWithOR: Bool) -> FTS5Pattern? {
        guard !terms.isEmpty else { return nil }
        let parts = terms.map { "\"\($0)\"*" }
        let raw = parts.joined(separator: joinWithOR ? " OR " : " ")
        return try? FTS5Pattern(rawPattern: raw)
    }

    /// Whether `word` (already lowercased) is a stopword. Used by synonym
    /// expansion to drop filler neighbours.
    static func isStopword(_ word: String) -> Bool {
        stopwords.contains(word)
    }

    private static func tokenize(_ query: String) -> [String] {
        query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// Compact English stopword set: articles, pronouns, prepositions,
    /// conjunctions, be/aux/modal verbs, wh-words, and a few instruction fillers
    /// ("show me everything about…"). Kept deliberately generic so it never
    /// strips a topical word.
    private static let stopwords: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those",
        "is", "am", "are", "was", "were", "be", "been", "being",
        "do", "does", "did", "doing", "done",
        "have", "has", "had", "having",
        "can", "could", "will", "would", "shall", "should", "may", "might", "must",
        "i", "me", "my", "mine", "myself", "we", "us", "our", "you", "your",
        "he", "him", "his", "she", "her", "it", "its", "they", "them", "their",
        "who", "whom", "whose", "what", "which", "when", "where", "why", "how",
        "of", "to", "in", "on", "at", "for", "with", "from", "by", "as", "into",
        "about", "over", "under", "up", "down", "out", "off", "than", "then",
        "and", "or", "but", "if", "so", "because", "while", "though",
        "not", "no", "yes", "all", "any", "some", "more", "most", "such",
        "just", "very", "too", "also", "even", "only", "here", "there",
        "show", "showme", "find", "get", "give", "tell", "see", "want", "need",
        "please", "let", "make", "look", "search",
        "someone", "something", "anyone", "anything", "everyone", "everything",
    ]
}
