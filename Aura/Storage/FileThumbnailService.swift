import Foundation
import AppKit
import QuickLookThumbnailing

/// Generates Quick Look content thumbnails for arbitrary files — a PDF's first
/// page, a video frame, a document cover, etc. Fully local (no network).
enum FileThumbnailService {
    struct Thumb {
        var data: Data
        var width: Int
        var height: Int
    }

    static func make(forFileURL url: URL, maxPixel: CGFloat = 600, scale: CGFloat = 2) async -> Thumb? {
        let pointSize = CGSize(width: maxPixel / scale, height: maxPixel / scale)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: pointSize,
            scale: scale,
            representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let cgImage = representation.cgImage
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return nil
        }
        return Thumb(data: data, width: cgImage.width, height: cgImage.height)
    }
}
