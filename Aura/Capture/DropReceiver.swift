import AppKit
import UniformTypeIdentifiers
import os

/// Decodes dropped `NSItemProvider`s into `CaptureCandidate`s. Used by the
/// notch panel's drop destination. Loading is async; results are delivered on
/// the main queue.
enum DropReceiver {
    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .text, .plainText]

    private static let log = Logger(subsystem: "app.captureaura", category: "capture")

    static func handle(_ providers: [NSItemProvider], emit: @escaping (CaptureCandidate) -> Void) {
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
