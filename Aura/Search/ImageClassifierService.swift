import Foundation
import Vision
import ImageIO
import os

/// On-device image classification via Vision's `VNClassifyImageRequest`
/// (macOS 10.15+, Neural Engine, no cloud). Classifies a saved image against
/// the built-in ~1,300-label taxonomy (animals, scenes, objects, food …) and
/// returns a short comma-separated list of high-confidence labels
/// ("dog, canine, animal, pet"), or nil when nothing clears the precision bar.
///
/// Synchronous + CPU/ANE-bound; callers offload it off the main actor (see
/// `DataStore.enrichForSearch`), same pattern as `OCRService`.
enum ImageClassifierService {
    private static let log = Logger(subsystem: "app.captureaura", category: "classify")
    private static let maxLabels = 12
    /// Vision's scene/object classifier operates on a small normalized input, so
    /// a 1024 px decode is ample — and avoids materializing a full-resolution
    /// bitmap for every image during the launch backfill (see `OCRService`).
    private static let maxPixel: CGFloat = 1024

    static func labels(for url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = ThumbnailService.cgThumbnail(from: source, maxPixel: maxPixel) else { return nil }

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            log.error("classification failed: \(error.localizedDescription)")
            return nil
        }

        // High-precision filter (Apple's recommended pattern): keep labels the
        // model is confident about, drop the speculative tail.
        let picked = (request.results ?? [])
            .filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
            .prefix(Self.maxLabels)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }

        guard !picked.isEmpty else { return nil }
        return picked.joined(separator: ", ")
    }
}
