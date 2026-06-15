import AppKit

/// Memory cache for on-disk images (link/OG hero art, file previews). Downsamples
/// on load and is bounded by **bytes** — not just object count — so a vault full
/// of large images can't accumulate hundreds of MB of decoded bitmaps and push a
/// low-RAM Mac into swap. Flushed automatically under memory pressure (see
/// `BoundedImageCache` / `ImageCache`).
enum DiskImage {
    /// Hero/OG art renders at card width; ~900 px is plenty and keeps each
    /// decoded bitmap to a few MB instead of tens.
    private static let maxPixel: CGFloat = 900
    private static let cache = BoundedImageCache(countLimit: 150,
                                                 costLimitBytes: 80 * 1024 * 1024)

    static func load(_ url: URL?) -> NSImage? {
        guard let url else { return nil }
        let key = url.path
        if let cached = cache.object(forKey: key) { return cached }
        guard let (image, cost) = ImageDownsampler.image(fromURL: url, maxPixel: maxPixel) else { return nil }
        cache.set(image, forKey: key, cost: cost)
        return image
    }
}
