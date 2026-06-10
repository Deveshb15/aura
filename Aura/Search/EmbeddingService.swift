import Foundation
import NaturalLanguage
import os

/// On-device sentence embeddings via NaturalLanguage's `NLContextualEmbedding`
/// (BERT-class, contextual, 512-dim, on-device from macOS 14 — no model bundled
/// and no cloud). Token vectors are mean-pooled and L2-normalized into a single
/// document vector, so downstream cosine similarity is a plain dot product.
///
/// An `actor` so the model is loaded once and accessed serially off the main
/// thread; embedding a snippet is single-digit milliseconds on Apple Silicon.
actor EmbeddingService {
    static let shared = EmbeddingService()

    /// Stable id persisted next to every vector. Bump it if we ever change the
    /// model so a backfill can detect stale vectors and re-embed.
    static let modelIdentifier = "nl-contextual.english.v1"

    private let log = Logger(subsystem: "app.captureaura", category: "embedding")
    private var model: NLContextualEmbedding?
    private var loaded = false
    private var assetsRequested = false

    /// NLContextualEmbedding handles ~256 tokens per call; cap the corpus so a
    /// long article embeds its representative head rather than failing.
    private let maxCharacters = 2_000

    /// Kick off model load (and a one-time asset download if needed) ahead of
    /// first use. Safe to call repeatedly.
    func prepare() async {
        _ = await ensureLoaded()
    }

    /// Embed text into a normalized 512-dim vector, or nil if the model isn't
    /// ready (assets still downloading) or the text is empty.
    func embed(_ text: String) async -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, await ensureLoaded(), let model else { return nil }

        let input = String(trimmed.prefix(maxCharacters))
        let dim = model.dimension
        guard dim > 0 else { return nil }

        do {
            let result = try model.embeddingResult(for: input, language: .english)
            var sum = [Double](repeating: 0, count: dim)
            var count = 0
            result.enumerateTokenVectors(in: input.startIndex..<input.endIndex) { vector, _ in
                guard vector.count == dim else { return true }
                for i in 0..<dim { sum[i] += vector[i] }
                count += 1
                return true
            }
            guard count > 0 else { return nil }

            // Mean-pool, convert to Float, and L2-normalize in one pass.
            var mean = [Float](repeating: 0, count: dim)
            let inv = 1.0 / Double(count)
            var normSq = 0.0
            for i in 0..<dim {
                let m = sum[i] * inv
                mean[i] = Float(m)
                normSq += m * m
            }
            let norm = sqrt(normSq)
            guard norm > 1e-9 else { return nil }
            let invNorm = Float(1.0 / norm)
            for i in 0..<dim { mean[i] *= invNorm }
            return mean
        } catch {
            log.error("embeddingResult failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Model lifecycle

    private func ensureLoaded() async -> Bool {
        if loaded, model != nil { return true }
        guard let m = model ?? NLContextualEmbedding(language: .english) else {
            log.error("NLContextualEmbedding unavailable for English")
            return false
        }
        model = m

        if !m.hasAvailableAssets {
            // Request the downloadable assets once; until they arrive, callers
            // get nil and search falls back to keyword-only.
            guard !assetsRequested else { return false }
            assetsRequested = true
            let available = await requestAssets(m)
            guard available else { return false }
        }

        do {
            try m.load()
            loaded = true
            return true
        } catch {
            log.error("NLContextualEmbedding load failed: \(error.localizedDescription)")
            return false
        }
    }

    private func requestAssets(_ model: NLContextualEmbedding) async -> Bool {
        do {
            // Imported (with "omit needless words") as `requestAssets()`, async.
            return try await model.requestAssets() == .available
        } catch {
            log.error("NLContextualEmbedding asset request failed: \(error.localizedDescription)")
            return false
        }
    }
}
