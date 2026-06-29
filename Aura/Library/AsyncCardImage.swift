import SwiftUI

/// Loads a cached, downsampled `NSImage` OFF the main thread and renders it once
/// ready, showing a placeholder until then.
///
/// The card views used to call `ThumbnailCache.image(...)` / `DiskImage.load(...)`
/// **synchronously inside their SwiftUI `body`**, so a cold image decode ran on
/// the main thread during layout/scroll — the source of grid jank and the
/// "decode every card at once" first-paint memory spike. Here the decode runs in
/// a detached task instead. The underlying caches (`ThumbnailCache` / `DiskImage`,
/// both thread-safe `NSCache`s, byte-bounded and flushed under memory pressure)
/// make a warm hit resolve almost immediately; only the cold path is deferred.
///
/// `id` is the load's identity: the background task re-runs only when it changes
/// (e.g. a link's hero arrives after enrichment), and the resolved image persists
/// across ordinary re-renders. Mirrors `AsyncLogo`.
struct AsyncCardImage<Content: View, Placeholder: View>: View {
    let id: String
    let load: @Sendable () -> NSImage?
    @ViewBuilder let content: (NSImage) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                placeholder()
            }
        }
        .task(id: id) {
            let loaded = await Task.detached(priority: .userInitiated, operation: load).value
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
