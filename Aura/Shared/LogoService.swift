import AppKit

/// Resolves a brand/source logo on demand, cached forever on disk.
///
/// Two entry points:
///   • `logo(for: domain)` — web sources (host/sourceURL): logo.dev → Google favicon.
///   • `logo(forAppNamed:)` — app sources ("Wispr Flow"): resolve a domain from
///     the app name (built-in map → slug-probe logo.dev), then fall back to the
///     app's own macOS icon, so *any* app gets a logo without a hardcoded list.
///
/// Everything is cached on disk (by domain, or by app slug) and de-duped
/// in-flight, so a grid full of the same source triggers a single fetch.
actor LogoService {
    static let shared = LogoService()

    /// logo.dev publishable key (`pk_…`) — primary source for clean brand logos.
    static let publishableToken: String? = "pk_T14-h5nVQ3ejknMKL_13gQ"

    /// Set once at startup (see AppEnvironment) to the Assets/ base directory.
    private static var baseURL: URL?
    static func configure(baseURL: URL) { Self.baseURL = baseURL }

    /// TLDs to probe for an unmapped app's domain, most-likely first.
    private static let probeTLDs = ["com", "ai", "io", "app", "co", "so"]

    /// Byte-bounded and memory-pressure-flushed (logos are small, but 500 of
    /// them with no byte ceiling still added up on long-running sessions).
    private let memory = BoundedImageCache(countLimit: 500, costLimitBytes: 24 * 1024 * 1024)
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    // MARK: - Web domain

    func logo(for domain: String) async -> NSImage? {
        let key = domain.lowercased()
        if let cached = memory.object(forKey: key) { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<NSImage?, Never> { await self.resolve(domain: key) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { memory.set(image, forKey: key, cost: image.approxDecodedBytes) }
        return image
    }

    private func resolve(domain: String) async -> NSImage? {
        if let fileURL = Self.diskURL(for: domain),
           FileManager.default.fileExists(atPath: fileURL.path),
           let image = NSImage(contentsOf: fileURL) {
            return image
        }
        if let data = await logoDevData(domain: domain) {
            return persist(data, to: Self.diskURL(for: domain))
        }
        // Tokenless fallback for real web domains: Google's favicon service.
        if let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=64"),
           let data = await LinkMetadataService.fetchImageData(from: url, minPixel: 16) {
            return persist(data, to: Self.diskURL(for: domain))
        }
        return nil
    }

    // MARK: - App source

    func logo(forAppNamed rawName: String) async -> NSImage? {
        let slug = Self.cacheSlug(rawName)
        guard !slug.isEmpty else { return nil }
        let key = "app:\(slug)"
        if let cached = memory.object(forKey: key) { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<NSImage?, Never> { await self.resolveApp(rawName: rawName, slug: slug) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { memory.set(image, forKey: key, cost: image.approxDecodedBytes) }
        return image
    }

    private func resolveApp(rawName: String, slug: String) async -> NSImage? {
        // 1. Disk cache (positive + negative), so each app resolves once ever.
        if let png = Self.appDiskURL(slug: slug, ext: "png"),
           FileManager.default.fileExists(atPath: png.path),
           let image = NSImage(contentsOf: png) {
            return image
        }
        if let miss = Self.appDiskURL(slug: slug, ext: "miss"),
           FileManager.default.fileExists(atPath: miss.path) {
            return nil
        }

        // 2. Built-in map (instant, accurate for multi-word apps).
        if let domain = AppDomains.domain(for: rawName),
           let data = await logoDevData(domain: domain) {
            return persist(data, to: Self.appDiskURL(slug: slug, ext: "png"))
        }

        // 3. Slug-probe logo.dev across TLDs (the "search on the spot").
        if let candidate = Self.probeSlug(rawName) {
            for tld in Self.probeTLDs {
                if let data = await logoDevData(domain: "\(candidate).\(tld)") {
                    return persist(data, to: Self.appDiskURL(slug: slug, ext: "png"))
                }
            }
        }

        // 4. App icon fallback — exact, offline, for apps not on logo.dev.
        if let data = await Self.appIconPNG(named: rawName) {
            return persist(data, to: Self.appDiskURL(slug: slug, ext: "png"))
        }

        // 5. Negative cache so we don't re-probe a dead end.
        if let miss = Self.appDiskURL(slug: slug, ext: "miss") { try? Data().write(to: miss) }
        return nil
    }

    // MARK: - logo.dev fetch

    private func logoDevData(domain: String) async -> Data? {
        guard let token = Self.publishableToken,
              var comps = URLComponents(string: "https://img.logo.dev/\(domain)") else { return nil }
        comps.queryItems = [
            .init(name: "token", value: token),
            .init(name: "size", value: "64"),
            .init(name: "format", value: "png"),
            .init(name: "retina", value: "true"),
            .init(name: "fallback", value: "404"),   // 404 (not monogram) so we fall through
        ]
        guard let url = comps.url else { return nil }
        return await LinkMetadataService.fetchImageData(from: url, minPixel: 16)
    }

    private func persist(_ data: Data, to fileURL: URL?) -> NSImage? {
        if let fileURL { try? data.write(to: fileURL, options: .atomic) }
        return NSImage(data: data)
    }

    // MARK: - Slugs & paths

    /// Stable cache key: all alphanumerics of the name, lowercased.
    private static func cacheSlug(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Domain guess: words minus generic suffixes, concatenated ("Wispr Flow" →
    /// "wisprflow", "Brave Browser" → "brave"). Full-concat only (no first-word)
    /// to avoid false matches like "Aura Quick Note" → aura.com.
    private static func probeSlug(_ name: String) -> String? {
        let generic: Set<String> = ["browser", "app", "desktop", "beta", "preview",
                                     "dev", "mac", "macos", "client", "for", "the"]
        let words = name.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            .filter { !generic.contains($0) }
        let slug = words.joined()
        return slug.isEmpty ? nil : slug
    }

    private static func diskURL(for domain: String) -> URL? {
        guard let baseURL else { return nil }
        let safe = domain.replacingOccurrences(of: "/", with: "_")
        return baseURL.appendingPathComponent("logo/\(safe).png")
    }

    private static func appDiskURL(slug: String, ext: String) -> URL? {
        guard let baseURL else { return nil }
        return baseURL.appendingPathComponent("logo/app-\(slug).\(ext)")
    }

    /// The installed app's icon as a 64px PNG, if the app is found by name.
    private static func appIconPNG(named name: String) async -> Data? {
        let paths = [
            "/Applications/\(name).app",
            NSHomeDirectory() + "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app",
        ]
        guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
        return await MainActor.run {
            let icon = NSWorkspace.shared.icon(forFile: path)
            let size = NSSize(width: 64, height: 64)
            let canvas = NSImage(size: size)
            canvas.lockFocus()
            icon.draw(in: NSRect(origin: .zero, size: size))
            canvas.unlockFocus()
            guard let tiff = canvas.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return nil }
            return png
        }
    }
}
