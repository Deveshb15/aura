import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif
import os

/// Derives topical keyword tags for an item so related-term searches resolve via
/// the *existing* FTS prefix matcher: a note about a "trek" gets tagged
/// "hiking trekking outdoors travel adventure trail mountains", so a search for
/// "hike" (→ matches "hiking"), "travel", or "outdoors" finds it. The tags are
/// written to the item's `keywords` FTS column at enrich time — the query path
/// is untouched.
///
/// Two paths, picked at runtime:
///  - **macOS 26 + Apple Intelligence**: the on-device LLM reads the item with
///    full context and emits clean topical + category tags (handles abstraction
///    like "travel" that pure word-similarity can't).
///  - **Fallback** (older OS / AI off): expand the item's own salient nouns with
///    the on-device word embedding (`SynonymExpander`). Reliable for near-
///    synonyms ("trek" → "hiking") because document terms are unambiguous;
///    weaker on broad categories.
enum KeywordTagger {
    private static let log = Logger(subsystem: "app.captureaura", category: "tagger")

    /// Bump when the tagging logic changes so already-tagged items get re-tagged
    /// (see `DataStore.migrateKeywordTagsIfNeeded`).
    static let version = "kw-v5"   // v5 = skip tagging near-empty notes (anti-hallucination)

    /// Upper bound on tags kept (bounds the FTS column and any LLM output).
    static let maxTags = 18
    /// Below this many characters of source text there's nothing worth tagging.
    private static let minSourceLength = 6
    /// Cap on text handed to the tagger — the head is representative.
    private static let maxSourceLength = 2_000

    /// Space-joined tag string ready to store in `keywords`, or "" when the item
    /// has no taggable text (still stored, so the backfill doesn't retry it).
    static func tagString(for item: Item) async -> String {
        await tags(for: item).joined(separator: " ")
    }

    /// Deduped lowercase tags for `item` ([] if nothing meaningful).
    ///
    /// The LLM (when available) reliably names the specific activity AND its
    /// everyday synonyms (the prompt demands "a trek MUST include hiking,
    /// walking"). But it is unreliable about BROAD umbrellas it semantically
    /// resists — it tagged a local day-hike "outdoors" yet refused "travel" even
    /// when told it MUST. So umbrella consistency is enforced deterministically
    /// (`applyCategoryBoosters`), not left to the model: every outdoorsy item
    /// ends up under "travel"/"outdoors", so browse-by-category search is
    /// consistent. On older OSes (no LLM) the tag set is word-embedding
    /// neighbours of the item's salient nouns, then the same boosters.
    static func tags(for item: Item) async -> [String] {
        let source = taggingSource(for: item)
        // Need at least a couple of real words. A near-empty note ("DNameet@202615",
        // an ID, a single token) gives the LLM nothing to go on and it hallucinates
        // — it tagged that ID "travel, accommodation, vacation", polluting search.
        guard source.count >= minSourceLength, meaningfulWordCount(source) >= 2 else { return [] }

        let llm = (await llmTags(source: source)) ?? []
        var base: [String]
        if llm.isEmpty {
            // No LLM (macOS 14–25): neighbours of the item's salient nouns are the
            // whole tag set (trek → hiking, hiker, trail, …).
            let nouns = salientNouns(in: source, limit: 6)
            let synonyms = await SynonymExpander.shared.synonyms(for: nouns, maxTerms: 6)
            var seen = Set<String>()
            base = (nouns + synonyms).filter { seen.insert($0).inserted }
        } else {
            base = llm
        }
        return Array(applyCategoryBoosters(to: base, source: source).prefix(maxTags))
    }

    /// Count of distinct alphabetic word tokens (≥3 chars) — a cheap "is there
    /// real content here" signal that excludes IDs, codes, and single tokens.
    private static func meaningfulWordCount(_ text: String) -> Int {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 3 }).count
    }

    // MARK: - Category boosters (deterministic umbrella consistency)

    /// Clusters that force a broad umbrella the LLM judges inconsistently. If an
    /// item's tags or source text contain any trigger word, its umbrellas are
    /// guaranteed in the tag set — so e.g. a search for "travel" surfaces EVERY
    /// outdoorsy item, not just the ones the model decided were "travel".
    private static let categoryBoosters: [(triggers: Set<String>, umbrellas: [String])] = [
        (["hike", "hiking", "hikes", "hiker", "hikers", "trek", "trekking", "trekker",
          "trekkers", "trail", "trails", "trailhead", "backpacking", "camping",
          "mountaineering", "summit", "waterfall", "waterfalls", "falls", "campsite"],
         ["hiking", "walking", "outdoors", "travel", "adventure", "nature"]),
        (["hotel", "hostel", "hostels", "backpackers", "airbnb", "booking", "bookings",
          "accommodation", "flight", "flights", "itinerary", "tourism", "sightseeing",
          "destination", "vacation", "holiday"],
         ["travel", "trip", "tourism", "accommodation"]),
    ]

    /// Umbrellas placed FIRST so the `maxTags` cap can never drop them; specific
    /// tags follow. (FTS is order-agnostic — this is purely about surviving the cap.)
    private static func applyCategoryBoosters(to tags: [String], source: String) -> [String] {
        let haystack = Set((tags.joined(separator: " ") + " " + source.lowercased())
            .split { !$0.isLetter }.map(String.init))
        var result: [String] = []
        var seen = Set<String>()
        for booster in categoryBoosters where !booster.triggers.isDisjoint(with: haystack) {
            for umbrella in booster.umbrellas where seen.insert(umbrella).inserted {
                result.append(umbrella)
            }
        }
        for tag in tags where seen.insert(tag).inserted { result.append(tag) }
        return result
    }

    /// Text we tag from: title + mined body + link description + raw content,
    /// trimmed to the representative head.
    private static func taggingSource(for item: Item) -> String {
        let joined = [item.title, item.extractedText, item.ogDescription, item.textContent]
            .compactMap { $0 }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(joined.prefix(maxSourceLength))
    }

    // MARK: - LLM path (macOS 26+)

    private static func llmTags(source: String) async -> [String]? {
        guard #available(macOS 26.0, *), AnswerService.isAvailable else { return nil }
        return await LLMTagger.tags(source: source, maxTags: maxTags)
    }

    // MARK: - Salient-noun extraction (seeds for neighbour expansion)

    /// Most frequent nouns in `text`, lowercased, ≥3 chars, non-stopword.
    private static func salientNouns(in text: String, limit: Int) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var counts: [String: Int] = [:]
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word,
                             scheme: .lexicalClass, options: options) { tag, range in
            guard tag == .noun else { return true }
            let word = text[range].lowercased()
            if word.count >= 3, word.allSatisfy({ $0.isLetter }), !QueryDistiller.isStopword(word) {
                counts[word, default: 0] += 1
            }
            return true
        }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }
}

@available(macOS 26.0, *)
private enum LLMTagger {
    static func tags(source: String, maxTags: Int) async -> [String]? {
        let instructions = """
        You label saved items for a personal search vault so they can be found by \
        ANY word someone might later search. Given the text of ONE item, reply with \
        a single comma-separated line of up to 14 lowercase keywords. Include: \
        (1) the specific topics in the text, (2) the broader category or activity, \
        and (3) CRUCIALLY the two or three most common everyday SYNONYMS for the \
        main activity even if the text never uses them — e.g. a trekking trip MUST \
        include "hiking" and "walking"; a flight, hotel, or itinerary MUST include \
        "travel"; a film MUST include "movie"; a car MUST include "automobile". \
        Output ONLY the comma-separated keywords: no sentences, no numbering, no \
        hashtags, no explanation.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let options = GenerationOptions(maximumResponseTokens: 90)
            let response = try await session.respond(to: source, options: options)
            return parse(response.content, maxTags: maxTags)
        } catch {
            return nil
        }
    }

    /// Split the model's comma/newline list into clean single/short tags.
    static func parse(_ raw: String, maxTags: Int) -> [String] {
        var seen = Set<String>()
        return raw
            .replacingOccurrences(of: "\n", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t#.-•*")).lowercased() }
            .filter { tag in
                tag.count >= 2 && tag.count <= 30
                    && tag.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " }
                    && seen.insert(tag).inserted
            }
            .prefix(maxTags)
            .map { String($0) }
    }
}
