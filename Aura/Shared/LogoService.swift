import AppKit

/// Resolves a brand/source logo for a web domain, on demand, cached forever on
/// disk by domain (logos are reusable across every item from the same site).
///
/// Resolution chain, first hit wins:
///   memory cache → on-disk `logo/{domain}.png` → logo.dev (if a token is set)
///   → Google's favicon service (tokenless).
/// Concurrent requests for the same domain share one in-flight Task, so a grid
/// full of github.com cards triggers a single fetch.
actor LogoService {
    static let shared = LogoService()

    /// logo.dev publishable key (`pk_…`) — primary source for clean brand
    /// logos. If a domain has no logo.dev match, the chain falls through to
    /// Google's favicon service automatically.
    static let publishableToken: String? = "pk_T14-h5nVQ3ejknMKL_13gQ"

    /// Set once at startup (see AppEnvironment) to the Assets/ base directory.
    private static var baseURL: URL?
    static func configure(baseURL: URL) { Self.baseURL = baseURL }

    private let memory: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>(); c.countLimit = 500; return c
    }()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func logo(for domain: String) async -> NSImage? {
        let key = domain.lowercased()
        if let cached = memory.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<NSImage?, Never> { await resolve(domain: key) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }

    private func resolve(domain: String) async -> NSImage? {
        // 1. On-disk cache (survives launches, shared across items).
        if let fileURL = Self.diskURL(for: domain),
           FileManager.default.fileExists(atPath: fileURL.path),
           let image = NSImage(contentsOf: fileURL) {
            return image
        }

        // 2. logo.dev (clean square brand logos) when a token is configured.
        if let token = Self.publishableToken,
           var comps = URLComponents(string: "https://img.logo.dev/\(domain)") {
            comps.queryItems = [
                .init(name: "token", value: token),
                .init(name: "size", value: "64"),
                .init(name: "format", value: "png"),
                .init(name: "retina", value: "true"),
                .init(name: "fallback", value: "404"),   // 404 (not monogram) so we fall through
            ]
            if let url = comps.url,
               let data = await LinkMetadataService.fetchImageData(from: url, minPixel: 16) {
                return persist(data, for: domain)
            }
        }

        // 3. Tokenless fallback: Google's favicon service (works for any domain).
        if let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=64"),
           let data = await LinkMetadataService.fetchImageData(from: url, minPixel: 16) {
            return persist(data, for: domain)
        }
        return nil
    }

    /// Writes the bytes to the deterministic per-domain path and returns the image.
    private func persist(_ data: Data, for domain: String) -> NSImage? {
        if let fileURL = Self.diskURL(for: domain) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return NSImage(data: data)
    }

    private static func diskURL(for domain: String) -> URL? {
        guard let baseURL else { return nil }
        let safe = domain.replacingOccurrences(of: "/", with: "_")
        return baseURL.appendingPathComponent("logo/\(safe).png")
    }
}
