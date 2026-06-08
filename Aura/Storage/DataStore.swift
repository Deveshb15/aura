import Foundation
import AppKit
import Observation
import GRDB

/// The single source of truth shared by BOTH surfaces (the notch panel and the
/// library window). Wraps a GRDB `DatabasePool`, publishes reactive item arrays
/// via `ValueObservation`, and exposes the one `save()` path used by the
/// clipboard nudge and drag-and-drop alike.
@MainActor
@Observable
final class DataStore {
    private let dbPool: DatabasePool
    private let assetStore: AssetStore

    private(set) var libraryItems: [Item] = []
    private(set) var recentItems: [Item] = []

    /// Called whenever we write to the pasteboard ourselves, so the clipboard
    /// watcher can ignore that change and avoid nudging our own copy-back.
    var onSelfCopy: ((Int) -> Void)?

    @ObservationIgnored private var observationCancellable: AnyDatabaseCancellable?

    init(dbPool: DatabasePool, assetStore: AssetStore) {
        self.dbPool = dbPool
        self.assetStore = assetStore
        startObserving()
    }

    private func startObserving() {
        let observation = ValueObservation.tracking { db in
            try Item.order(Column("createdAt").desc).limit(400).fetchAll(db)
        }
        observationCancellable = observation.start(
            in: dbPool,
            scheduling: .immediate,
            onError: { error in
                NSLog("Aura: item observation error: \(error)")
            },
            onChange: { [weak self] items in
                guard let self else { return }
                self.libraryItems = items
                self.recentItems = Array(items.prefix(40))
            }
        )
    }

    // MARK: - Save (single path for nudge + drag-drop)

    func save(_ candidate: CaptureCandidate) async {
        var item = Item(type: .text)
        item.sourceApp = candidate.sourceApp
        item.sourceURL = candidate.sourceURL

        switch candidate.payload {
        case .text(let string):
            item.type = ItemType.text.rawValue
            item.textContent = string
            item.title = Self.titleSnippet(from: string)

        case .url(let url):
            item.type = ItemType.url.rawValue
            item.textContent = url.absoluteString
            item.host = url.host
            item.title = url.host ?? url.absoluteString
            item.urlSubtype = URLClassifier.subtype(for: url).rawValue

        case .color(let hex):
            item.type = ItemType.color.rawValue
            item.textContent = hex
            item.colorHex = hex
            item.title = hex

        case .image(let data):
            populateImage(&item, data: data)

        case .file(let url):
            if AssetStore.isImageFile(url), let data = try? Data(contentsOf: url) {
                populateImage(&item, data: data, originalName: url.lastPathComponent)
            } else {
                item.type = ItemType.file.rawValue
                if let stored = try? assetStore.storeFile(at: url) {
                    item.assetPath = stored.relativePath
                    item.uti = stored.uti
                    item.byteSize = stored.byteSize
                    item.fileName = stored.fileName
                }
                item.title = url.lastPathComponent
                item.fileName = url.lastPathComponent
            }
        }

        do {
            try await dbPool.write { [item] db in
                try item.insert(db)
            }
        } catch {
            NSLog("Aura: save failed: \(error)")
        }
    }

    private func populateImage(_ item: inout Item, data: Data, originalName: String? = nil) {
        item.type = ItemType.image.rawValue
        if let stored = try? assetStore.storeImageData(data) {
            item.assetPath = stored.relativePath
            item.uti = stored.uti
            item.byteSize = stored.byteSize
            item.fileName = originalName ?? stored.fileName
        }
        if let thumb = ThumbnailService.make(fromImageData: data) {
            item.thumbnail = thumb.data
            item.thumbWidth = thumb.width
            item.thumbHeight = thumb.height
        }
        item.title = originalName ?? "Image"
    }

    // MARK: - Retrieval (vault-only: copy out / drag out)

    func copyToClipboard(_ item: Item) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.itemType {
        case .image, .file:
            if let path = item.assetPath {
                pasteboard.writeObjects([assetStore.absoluteURL(for: path) as NSURL])
            } else if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .text, .url, .color:
            pasteboard.setString(item.textContent ?? item.title ?? "", forType: .string)
        }
        onSelfCopy?(pasteboard.changeCount)
    }

    func delete(_ item: Item) {
        let id = item.id
        let assetPath = item.assetPath
        let assetStore = self.assetStore
        Task {
            do {
                try await dbPool.write { db in
                    _ = try Item.deleteOne(db, key: id)
                }
                if let assetPath { assetStore.removeAsset(relativePath: assetPath) }
            } catch {
                NSLog("Aura: delete failed: \(error)")
            }
        }
    }

    func assetURL(for item: Item) -> URL? {
        guard let path = item.assetPath else { return nil }
        return assetStore.absoluteURL(for: path)
    }

    // MARK: - Helpers

    private static func titleSnippet(from string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        return String(firstLine.prefix(80))
    }
}
