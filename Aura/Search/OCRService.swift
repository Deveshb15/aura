import Foundation
import Vision
import ImageIO
import os

/// On-device optical character recognition for captured images, via Vision's
/// text recognizer (`VNRecognizeTextRequest`, available from macOS 10.15 — runs
/// on the Neural Engine, no cloud). Returns the recognized text, or nil if the
/// image holds nothing legible.
///
/// Synchronous + CPU/ANE-bound; callers offload it off the main actor (see
/// `DataStore.enrichForSearch`).
enum OCRService {
    private static let log = Logger(subsystem: "app.captureaura", category: "ocr")
    private static let maxCharacters = 10_000
    /// Decode the image downsampled to this pixel ceiling before recognition.
    /// 2048 px keeps even dense screenshots legible to Vision while turning a
    /// 6000×4000 capture's ~96 MB full-resolution bitmap into a few MB — the
    /// backfill OCRs up to 100 images per launch, so the full decode was a real
    /// memory spike. Recognition accuracy is unaffected at this size.
    private static let maxPixel: CGFloat = 2048

    static func recognizeText(in url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = ThumbnailService.cgThumbnail(from: source, maxPixel: maxPixel) else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            log.error("OCR failed: \(error.localizedDescription)")
            return nil
        }

        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(maxCharacters))
    }
}
