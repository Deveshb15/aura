import AppKit
import UniformTypeIdentifiers
import os

/// Decodes dropped `NSItemProvider`s into `CaptureCandidate`s. Used by the
/// notch panel's drop destination. Loading is async; results are delivered on
/// the main queue.
enum DropReceiver {
    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .text, .plainText, .html]

    private static let log = Logger(subsystem: "app.captureaura", category: "capture")

    static func handle(_ providers: [NSItemProvider], emit: @escaping (CaptureCandidate) -> Void) {
        // Prefer reading the live drag pasteboard directly. Many sources (notably
        // browser / web-app link and image drags) hand SwiftUI a single
        // NSItemProvider that advertises an exotic type (`public.html`,
        // `com.compuserve.gif`) but registers NO loader block — so every
        // loadObject / loadDataRepresentation fails with "No loader block
        // available" and nothing saves. The underlying drag pasteboard still has
        // the real bytes, read synchronously here while the drop is in progress.
        // The provider path below remains as a fallback for the rare source that
        // doesn't populate the drag pasteboard.
        if handleFromDragPasteboard(emit: emit) { return }
        handleViaProviders(providers, emit: emit)
    }

    // MARK: - Drag-pasteboard path (primary)

    /// Reads the live drag pasteboard and emits the first meaningful capture.
    /// Returns true if it handled the drop. Synchronous — valid only mid-drop.
    private static func handleFromDragPasteboard(emit: @escaping (CaptureCandidate) -> Void) -> Bool {
        let pb = NSPasteboard(name: .drag)
        let types = pb.types ?? []
        log.debug("drop: drag pasteboard types: \(types.map(\.rawValue), privacy: .public)")
        guard !types.isEmpty else { return false }

        // 1. Real file(s) on disk (Finder). Image files route to .image in save().
        let fileURLs = (pb.readObjects(forClasses: [NSURL.self],
                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !fileURLs.isEmpty {
            for url in fileURLs { emit(CaptureCandidate(payload: .file(url))) }
            return true
        }

        // 2. Inline image bytes (browser / app image & GIF drags).
        if let data = imageDataFromDragPasteboard(pb) {
            log.debug("drop: loaded image (\(data.count) bytes) from drag pasteboard")
            emit(CaptureCandidate(payload: .image(data)))
            return true
        }

        // 3. A web link — explicit public.url, or pulled out of the dragged HTML/text.
        if let url = webURLFromDragPasteboard(pb) {
            log.debug("drop: captured link \(url.absoluteString, privacy: .public) from drag pasteboard")
            emit(CaptureCandidate(payload: .url(url)))
            return true
        }

        // 4. Plain text.
        if let s = pb.string(forType: .string),
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log.debug("drop: captured \(s.count) chars of text from drag pasteboard")
            emit(CaptureCandidate.fromString(s))
            return true
        }

        // 5. HTML with no extractable link — strip tags so it's at least captured.
        if let html = pb.string(forType: .html),
           let text = strippedText(fromHTML: html), !text.isEmpty {
            log.debug("drop: captured \(text.count) chars of stripped HTML from drag pasteboard")
            emit(CaptureCandidate.fromString(text))
            return true
        }

        return false
    }

    /// First web link reachable from the drag pasteboard: an explicit `public.url`,
    /// else the first `href`/`src` in the dragged HTML, else a URL embedded in text.
    private static func webURLFromDragPasteboard(_ pb: NSPasteboard) -> URL? {
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL],
           let web = urls.first(where: { !$0.isFileURL && ($0.scheme == "http" || $0.scheme == "https") }) {
            return web
        }
        if let s = pb.string(forType: NSPasteboard.PasteboardType("public.url")),
           let url = CaptureCandidate.webURL(from: s) {
            return url
        }
        if let html = pb.string(forType: .html), let url = firstURL(inHTML: html) {
            return url
        }
        if let s = pb.string(forType: .string), let url = CaptureCandidate.firstWebURL(in: s) {
            return url
        }
        return nil
    }

    /// First `http(s)` URL referenced by an `href` or `src` attribute in HTML.
    private static func firstURL(inHTML html: String) -> URL? {
        for attr in ["href", "src"] {
            let pattern = "\(attr)\\s*=\\s*[\"']([^\"']+)[\"']"
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            for match in re.matches(in: html, range: range) {
                if let r = Range(match.range(at: 1), in: html),
                   let url = CaptureCandidate.webURL(from: String(html[r])) {
                    return url
                }
            }
        }
        return nil
    }

    /// Crude tag-strip so HTML with no link still captures as readable text.
    private static func strippedText(fromHTML html: String) -> String? {
        let text = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - NSItemProvider path (fallback)

    private static func handleViaProviders(_ providers: [NSItemProvider], emit: @escaping (CaptureCandidate) -> Void) {
        // A single drag — say an image out of a browser — usually arrives as
        // several providers: the image bytes PLUS the page/image source URL and
        // some marked-up text. When the drop carries an image at all, that's what
        // the user grabbed, so we capture it and skip the sibling link/text
        // providers. Otherwise a failed image load used to fall through and save
        // the source URL instead of the picture ("the number just goes up").
        let dropHasImage = providers.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }

        for provider in providers {
            log.debug("drop provider types: \(provider.registeredTypeIdentifiers, privacy: .public)")

            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url, url.isFileURL else {
                        log.error("drop: file-url load failed: \(String(describing: error), privacy: .public)")
                        return
                    }
                    DispatchQueue.main.async {
                        emit(CaptureCandidate(payload: .file(url)))
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                loadImage(from: provider, emit: emit)
            } else if !dropHasImage, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        emit(CaptureCandidate(payload: .url(url)))
                    }
                }
            } else if !dropHasImage, provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let string else { return }
                    DispatchQueue.main.async {
                        emit(CaptureCandidate.fromString(string))
                    }
                }
            }
        }
    }

    // MARK: - Image loading

    /// Loads image bytes from a provider, preserving the original encoding where
    /// possible.
    ///
    /// `loadDataRepresentation(forTypeIdentifier: "public.image")` — the abstract
    /// parent type — frequently returns nil for browser drags, which register
    /// only a *concrete* child (`public.png` / `public.jpeg` / `public.tiff`)
    /// with no data rep under the parent. (The clipboard path works precisely
    /// because it reads concrete `.png`/`.tiff`.) So we walk the concrete image
    /// types the provider actually advertises and try each in turn, then fall
    /// back to coercing an `NSImage`.
    private static func loadImage(from provider: NSItemProvider, emit: @escaping (CaptureCandidate) -> Void) {
        let imageTypes = provider.registeredTypeIdentifiers.filter {
            UTType($0)?.conforms(to: .image) == true
        }
        guard !imageTypes.isEmpty else {
            loadImageObjectFallback(from: provider, emit: emit)
            return
        }
        tryLoadImageData(from: provider, types: imageTypes, index: 0, emit: emit)
    }

    /// Raw image bytes from the live drag pasteboard, trying concrete image types
    /// in a sensible order and then any image-conforming type present. Returns the
    /// first non-empty payload, preserving the source encoding. Only meaningful
    /// while a drop is in progress (the drag pasteboard is valid then).
    private static func imageDataFromDragPasteboard(_ pb: NSPasteboard) -> Data? {
        let preferred = ["public.png", "public.jpeg", "com.compuserve.gif",
                         "public.heic", "public.tiff", "public.webp"]
        for id in preferred {
            let type = NSPasteboard.PasteboardType(id)
            if let data = pb.data(forType: type), !data.isEmpty { return data }
        }
        for type in pb.types ?? [] where UTType(type.rawValue)?.conforms(to: .image) == true {
            if let data = pb.data(forType: type), !data.isEmpty { return data }
        }
        return nil
    }

    /// Tries each concrete image UTI in order; on exhaustion, falls back to NSImage.
    private static func tryLoadImageData(from provider: NSItemProvider,
                                         types: [String],
                                         index: Int,
                                         emit: @escaping (CaptureCandidate) -> Void) {
        guard index < types.count else {
            log.error("drop: all concrete image types failed; trying NSImage fallback")
            loadImageObjectFallback(from: provider, emit: emit)
            return
        }
        let type = types[index]
        provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
            if let data {
                log.debug("drop: loaded image (\(data.count) bytes) as \(type, privacy: .public)")
                DispatchQueue.main.async {
                    emit(CaptureCandidate(payload: .image(data)))
                }
            } else {
                log.error("drop: image load failed for \(type, privacy: .public): \(String(describing: error), privacy: .public)")
                tryLoadImageData(from: provider, types: types, index: index + 1, emit: emit)
            }
        }
    }

    /// Last resort: coerce the provider into an `NSImage` and re-encode to PNG.
    /// Lossy versus the original bytes, but better than silently dropping the
    /// capture.
    private static func loadImageObjectFallback(from provider: NSItemProvider,
                                                emit: @escaping (CaptureCandidate) -> Void) {
        guard provider.canLoadObject(ofClass: NSImage.self) else {
            log.error("drop: provider cannot load NSImage; image capture lost")
            return
        }
        _ = provider.loadObject(ofClass: NSImage.self) { object, error in
            guard let image = object as? NSImage,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                log.error("drop: NSImage fallback failed: \(String(describing: error), privacy: .public)")
                return
            }
            log.debug("drop: captured image via NSImage fallback (\(png.count) bytes)")
            DispatchQueue.main.async {
                emit(CaptureCandidate(payload: .image(png)))
            }
        }
    }
}
