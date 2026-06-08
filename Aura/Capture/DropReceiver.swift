import AppKit
import UniformTypeIdentifiers

/// Decodes dropped `NSItemProvider`s into `CaptureCandidate`s. Used by the
/// notch panel's drop destination. Loading is async; results are delivered on
/// the main queue.
enum DropReceiver {
    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .text, .plainText]

    static func handle(_ providers: [NSItemProvider], emit: @escaping (CaptureCandidate) -> Void) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    DispatchQueue.main.async {
                        emit(CaptureCandidate(payload: .file(url)))
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async {
                        emit(CaptureCandidate(payload: .image(data)))
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        emit(CaptureCandidate(payload: .url(url)))
                    }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let string else { return }
                    DispatchQueue.main.async {
                        emit(CaptureCandidate.fromString(string))
                    }
                }
            }
        }
    }
}
