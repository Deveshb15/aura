import AppKit
import ImageIO
import os

/// Memory-pressure-aware registry for the app's in-memory image caches.
///
/// Loading full-resolution `NSImage`s and keeping them with only a *count*
/// limit was the primary driver of runaway memory on low-RAM (8 GB) machines:
/// the process pushes the whole system into swap and goes unresponsive (the
/// "freezes / can't even force-quit" symptom). The fix is twofold — every image
/// cache here is bounded by **bytes** and downsamples on load (see
/// `BoundedImageCache` / `ImageDownsampler`), and the single process-wide
/// memory-pressure monitor below flushes them all the moment the OS asks for
/// memory back, before the machine starts thrashing.
enum ImageCache {
    private static let log = Logger(subsystem: "app.captureaura", category: "memory")
    private static let lock = NSLock()
    private static var purgeHandlers: [() -> Void] = []
    private static var pressureSource: DispatchSourceMemoryPressure?

    /// Register a cache's flush closure. Called by `BoundedImageCache.init`.
    static func register(_ purge: @escaping () -> Void) {
        lock.lock(); purgeHandlers.append(purge); lock.unlock()
    }

    /// Flush every registered image cache.
    static func purgeAll() {
        lock.lock(); let handlers = purgeHandlers; lock.unlock()
        handlers.forEach { $0() }
    }

    /// Install the single process-wide memory-pressure monitor. Idempotent;
    /// call once at launch (see `AppDelegate`). On `.warning`/`.critical` the OS
    /// is telling us to shed memory *now* — dropping decoded bitmaps here keeps
    /// an 8 GB Mac out of the swap-thrash state where even Force Quit hangs.
    static func startMonitoringMemoryPressure() {
        lock.lock(); defer { lock.unlock() }
        guard pressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler {
            ImageCache.log.notice("Memory pressure — flushing image caches")
            ImageCache.purgeAll()
        }
        source.resume()
        pressureSource = source
    }
}

/// An `NSCache<NSString, NSImage>` bounded by **total decoded bytes** (not just
/// object count) and wired to flush under memory pressure. A single huge image
/// otherwise counts the same as a tiny favicon under a count-only limit, so the
/// real memory ceiling was effectively unbounded.
final class BoundedImageCache {
    private let cache = NSCache<NSString, NSImage>()

    init(countLimit: Int, costLimitBytes: Int) {
        cache.countLimit = countLimit
        cache.totalCostLimit = costLimitBytes
        ImageCache.register { [weak cache] in cache?.removeAllObjects() }
    }

    func object(forKey key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    func set(_ image: NSImage, forKey key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: max(cost, 1))
    }

    func removeAll() { cache.removeAllObjects() }
}

/// Downsamples image bytes/files to a pixel ceiling via ImageIO, returning the
/// decoded `NSImage` plus its approximate decoded-byte cost. ImageIO decodes
/// straight to the target size, so a 6000×3000 screenshot never materializes as
/// a ~70 MB bitmap just to fill a 280 pt card.
enum ImageDownsampler {
    static func image(from data: Data, maxPixel: CGFloat) -> (image: NSImage, cost: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return image(from: source, maxPixel: maxPixel)
    }

    static func image(fromURL url: URL, maxPixel: CGFloat) -> (image: NSImage, cost: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return image(from: source, maxPixel: maxPixel)
    }

    private static func image(from source: CGImageSource, maxPixel: CGFloat) -> (NSImage, Int)? {
        guard let cg = ThumbnailService.cgThumbnail(from: source, maxPixel: maxPixel) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        return (image, cg.width * cg.height * 4)
    }
}

/// Decoded, byte-bounded cache for the small JPEG thumbnails stored inline on
/// items. Keyed by item id (a thumbnail never changes for an id), so the bento
/// grid and recent strip stop re-decoding the same JPEG on every layout/scroll
/// pass — they decode once and reuse a cost-evicted `NSImage`.
enum ThumbnailCache {
    private static let cache = BoundedImageCache(countLimit: 300,
                                                 costLimitBytes: 64 * 1024 * 1024)

    static func image(id: String, data: Data) -> NSImage? {
        if let cached = cache.object(forKey: id) { return cached }
        if let (image, cost) = ImageDownsampler.image(from: data, maxPixel: 600) {
            cache.set(image, forKey: id, cost: cost)
            return image
        }
        // Fall back to a plain decode if ImageIO can't build a thumbnail.
        guard let image = NSImage(data: data) else { return nil }
        cache.set(image, forKey: id, cost: image.approxDecodedBytes)
        return image
    }
}

extension NSImage {
    /// Best-effort decoded size in bytes, from the largest bitmap representation
    /// (retina-aware via pixel dimensions), used as an `NSCache` cost.
    var approxDecodedBytes: Int {
        if let rep = representations.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
           rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return rep.pixelsWide * rep.pixelsHigh * 4
        }
        return max(1, Int(size.width * size.height * 4))
    }
}
