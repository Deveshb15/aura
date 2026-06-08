import AppKit

/// Tiny memory cache for on-disk thumbnails so the bento grid doesn't re-decode
/// the same image on every layout pass / scroll.
enum DiskImage {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    static func load(_ url: URL?) -> NSImage? {
        guard let url else { return nil }
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
