import Foundation
import FoundationModels

/// On-device conversational answer over the user's retrieved items, via Apple's
/// Foundation Models (macOS 26+, Apple Silicon, Apple Intelligence enabled).
/// The framework is generation-only — retrieval already happened upstream
/// (`HybridSearch`); this just synthesizes a short written answer grounded in
/// the top items. Everything that touches `FoundationModels` lives behind an
/// availability check, so the macOS 14 build links and runs fine on older /
/// Intel Macs (they simply never see an answer — the grid is the experience).
enum AnswerService {

    /// Whether the on-device model can be used right now. False on macOS < 26,
    /// Intel Macs, or when Apple Intelligence is disabled / still downloading.
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    /// Stream a concise written answer to `query`, grounded in `items`. Yields
    /// the cumulative answer text as it generates. Finishes immediately (no
    /// values) when unavailable or on error, so callers can just render
    /// whatever arrives without special-casing failure.
    static func streamAnswer(query: String, items: [Item]) -> AsyncStream<String> {
        guard #available(macOS 26.0, *), isAvailable else {
            return AsyncStream { $0.finish() }
        }
        return Responder.stream(query: query, items: items)
    }
}

@available(macOS 26.0, *)
private enum Responder {
    static func stream(query: String, items: [Item]) -> AsyncStream<String> {
        let instructions = """
        You are the memory of a personal capture vault called Aura. The user saved the items listed \
        in the prompt. Answer their question concisely (2–4 sentences), grounded ONLY in those items, \
        referring to them by title when useful. If nothing in the items answers the question, say so \
        plainly. Never invent facts or sources.
        """
        let prompt = buildPrompt(query: query, items: items)

        return AsyncStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let options = GenerationOptions(maximumResponseTokens: 350)
                    for try await snapshot in session.streamResponse(to: prompt, options: options) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Token-budgeted grounding context: the top few items, each trimmed, so we
    /// stay well within the model's ~4K context window.
    private static func buildPrompt(query: String, items: [Item]) -> String {
        let top = items.prefix(5)
        var lines: [String] = ["Saved items:"]
        for (index, item) in top.enumerated() {
            let title = item.title ?? item.host ?? item.fileName ?? "Untitled"
            let kind = item.itemType.rawValue
            let body = (item.extractedText ?? item.ogDescription ?? item.textContent ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = String(body.prefix(600))
            lines.append("\(index + 1). [\(kind)] \(title)" + (snippet.isEmpty ? "" : " — \(snippet)"))
        }
        lines.append("")
        lines.append("Question: \(query)")
        return lines.joined(separator: "\n")
    }
}
