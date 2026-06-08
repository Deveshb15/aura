import Foundation
import AppKit
import ImageIO

/// Generates small, memory-efficient thumbnails using ImageIO downsampling so
/// the bento grid never loads full-resolution images.
enum ThumbnailService {
    struct Thumb {
        var data: Data
        var width: Int
        var height: Int
    }

    static func make(fromImageData data: Data, maxPixel: CGFloat = 600) -> Thumb? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return make(from: source, maxPixel: maxPixel)
    }

    static func make(fromFileURL url: URL, maxPixel: CGFloat = 600) -> Thumb? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return make(from: source, maxPixel: maxPixel)
    }

    private static func make(from source: CGImageSource, maxPixel: CGFloat) -> Thumb? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return nil
        }
        return Thumb(data: data, width: cgImage.width, height: cgImage.height)
    }
}
