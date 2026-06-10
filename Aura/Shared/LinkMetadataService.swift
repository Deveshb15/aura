import Foundation
import AppKit
import ImageIO
@preconcurrency import LinkPresentation

/// Rich metadata fetched for a saved URL. Image/icon are raw bytes; the caller
/// downsamples + persists them.
struct LinkMetadata {
    var title: String?
    var description: String?
    var imageData: Data?
    var iconData: Data?
}

/// Fetches Open Graph–style preview metadata for a URL.
/// Strategy: YouTube special-case → Apple's LinkPresentation → manual OG scrape.
/// Runs entirely off the main actor (it's a non-isolated enum), so callers can
/// `await` it without blocking the UI.
enum LinkMetadataService {
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func fetch(url: URL) async -> LinkMetadata {
        switch URLClassifier.subtype(for: url) {
        case .youtube:
            if let yt = await YouTube.metadata(for: url) { return yt }
        case .vimeo:
            if let vm = await Vimeo.metadata(for: url) { return vm }
        default:
            break
        }

        let lp = await fetchViaLinkPresentation(url: url)
        if let lp, lp.imageData != nil {
            return lp
        }

        // LinkPresentation gave no image — try a manual Open Graph scrape and
        // merge whatever each found.
        let og = await fetchViaOpenGraph(url: url)
        return LinkMetadata(
            title: lp?.title ?? og?.title,
            description: lp?.description ?? og?.description,
            imageData: lp?.imageData ?? og?.imageData,
            iconData: lp?.iconData ?? og?.iconData
        )
    }

    /// Fetches the page and extracts its readable body text, for the search
    /// index. Video hosts are skipped — their "body" is JS chrome, and their
    /// title/description already come from oEmbed (see `fetch`).
    static func fetchArticleText(url: URL) async -> String? {
        guard !URLClassifier.subtype(for: url).isVideo else { return nil }
        guard let html = await fetchHTML(url: url) else { return nil }
        return ArticleExtractor.extractText(fromHTML: html, url: url)
    }

    // MARK: - LinkPresentation

    private static func fetchViaLinkPresentation(url: URL) async -> LinkMetadata? {
        let metadata: LPLinkMetadata? = await withCheckedContinuation { continuation in
            let provider = LPMetadataProvider()
            provider.timeout = 10
            provider.startFetchingMetadata(for: url) { [provider] metadata, error in
                _ = provider // retain until the callback fires
                continuation.resume(returning: error == nil ? metadata : nil)
            }
        }
        guard let metadata else { return nil }

        async let image = pngData(from: metadata.imageProvider)
        async let icon = pngData(from: metadata.iconProvider)
        return LinkMetadata(title: metadata.title, description: nil, imageData: await image, iconData: await icon)
    }

    private static func pngData(from provider: NSItemProvider?) async -> Data? {
        guard let provider, provider.canLoadObject(ofClass: NSImage.self) else { return nil }
        let image: NSImage? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                continuation.resume(returning: object as? NSImage)
            }
        }
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png
    }

    // MARK: - Open Graph scrape (fallback, no third-party deps)

    private static func fetchViaOpenGraph(url: URL) async -> LinkMetadata? {
        guard let html = await fetchHTML(url: url) else { return nil }

        let title = metaContent(html, key: "og:title") ?? htmlTitle(html)
        let description = metaContent(html, key: "og:description")
        var imageData: Data?
        if let imageURLString = metaContent(html, key: "og:image"),
           let imageURL = URL(string: imageURLString, relativeTo: url) {
            imageData = await fetchImageData(from: imageURL.absoluteURL, minPixel: 40)
        }
        let iconData = await fetchFavicon(for: url, html: html)

        if title == nil && imageData == nil && iconData == nil { return nil }
        return LinkMetadata(title: title, description: description, imageData: imageData, iconData: iconData)
    }

    private static func fetchHTML(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<400).contains($0.statusCode) }) ?? true else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func fetchFavicon(for url: URL, html: String) async -> Data? {
        var iconURL: URL?
        if let href = iconHref(html), let resolved = URL(string: href, relativeTo: url) {
            iconURL = resolved.absoluteURL
        } else if let host = url.host, let scheme = url.scheme {
            iconURL = URL(string: "\(scheme)://\(host)/favicon.ico")
        }
        guard let iconURL else { return nil }
        return await fetchImageData(from: iconURL, minPixel: 0)
    }

    // MARK: - Networking / image validation

    /// Fetches an image and returns its bytes only if it decodes and its largest
    /// dimension is at least `minPixel` (rejects 404 pages and tiny placeholders).
    static func fetchImageData(from url: URL, minPixel: CGFloat) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let width = (props[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
        guard max(width, height) >= minPixel else { return nil }
        return data
    }

    // MARK: - Lightweight HTML parsing

    private static func metaContent(_ html: String, key: String) -> String? {
        for tag in tags(in: html, named: "meta") {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            if tag.range(of: "(property|name)\\s*=\\s*[\"']\(escaped)[\"']",
                         options: [.regularExpression, .caseInsensitive]) != nil,
               let content = attribute(tag, "content"), !content.isEmpty {
                return content
            }
        }
        return nil
    }

    private static func iconHref(_ html: String) -> String? {
        var fallback: String?
        for tag in tags(in: html, named: "link") {
            guard tag.range(of: "rel\\s*=\\s*[\"'][^\"']*icon[^\"']*[\"']",
                            options: [.regularExpression, .caseInsensitive]) != nil,
                  let href = attribute(tag, "href") else { continue }
            // Prefer apple-touch-icon (larger, nicer) when present.
            if tag.range(of: "apple-touch-icon", options: .caseInsensitive) != nil { return href }
            fallback = fallback ?? href
        }
        return fallback
    }

    private static func htmlTitle(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>([\\s\\S]*?)</title>", options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else { return nil }
        let title = ns.substring(with: match.range(at: 1)).htmlDecoded().trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func tags(in html: String, named name: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<\(name)\\b[^>]*>", options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static func attribute(_ tag: String, _ name: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\b\(name)\\s*=\\s*[\"']([^\"']*)[\"']", options: [.caseInsensitive]) else { return nil }
        let ns = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1)).htmlDecoded()
    }
}

private extension String {
    /// Decodes the handful of HTML entities that commonly appear in meta tags.
    func htmlDecoded() -> String {
        var result = self
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#x27;": "'",
                        "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}

/// YouTube needs no scraping — thumbnails live on a predictable CDN and titles
/// come from the public oEmbed endpoint.
enum YouTube {
    static func videoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host == "youtu.be" {
            return url.pathComponents.dropFirst().first
        }
        guard host.contains("youtube.") else { return nil }
        if url.path == "/watch",
           let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let value = items.first(where: { $0.name == "v" })?.value {
            return value
        }
        let parts = url.pathComponents
        if let index = parts.firstIndex(where: { $0 == "embed" || $0 == "shorts" || $0 == "live" }),
           index + 1 < parts.count {
            return parts[index + 1]
        }
        return nil
    }

    static func metadata(for url: URL) async -> LinkMetadata? {
        guard let id = videoID(from: url) else { return nil }

        var title: String?
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [.init(name: "url", value: url.absoluteString), .init(name: "format", value: "json")]
        if let oembedURL = components.url,
           let (data, _) = try? await URLSession.shared.data(from: oembedURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            title = object["title"] as? String
        }

        for quality in ["maxresdefault", "sddefault", "hqdefault"] {
            if let thumbURL = URL(string: "https://img.youtube.com/vi/\(id)/\(quality).jpg"),
               let data = await LinkMetadataService.fetchImageData(from: thumbURL, minPixel: 200) {
                return LinkMetadata(title: title, description: nil, imageData: data, iconData: nil)
            }
        }
        return LinkMetadata(title: title, description: nil, imageData: nil, iconData: nil)
    }
}

/// Vimeo's public oEmbed endpoint returns title, description, and a thumbnail
/// URL with no scraping — giving video items real searchable text.
enum Vimeo {
    static func metadata(for url: URL) async -> LinkMetadata? {
        var components = URLComponents(string: "https://vimeo.com/api/oembed.json")!
        components.queryItems = [.init(name: "url", value: url.absoluteString)]
        guard let oembedURL = components.url,
              let (data, _) = try? await URLSession.shared.data(from: oembedURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (object["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var imageData: Data?
        if let thumb = object["thumbnail_url"] as? String, let thumbURL = URL(string: thumb) {
            imageData = await LinkMetadataService.fetchImageData(from: thumbURL, minPixel: 100)
        }

        if title == nil, description == nil, imageData == nil { return nil }
        return LinkMetadata(title: title, description: description, imageData: imageData, iconData: nil)
    }
}
