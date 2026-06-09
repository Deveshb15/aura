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
    private(set) var collections: [ItemCollection] = []

    /// Called whenever we write to the pasteboard ourselves, so the clipboard
    /// watcher can ignore that change and avoid nudging our own copy-back.
    var onSelfCopy: ((Int) -> Void)?

    @ObservationIgnored private var itemsCancellable: AnyDatabaseCancellable?
    @ObservationIgnored private var collectionsCancellable: AnyDatabaseCancellable?

    init(dbPool: DatabasePool, assetStore: AssetStore) {
        self.dbPool = dbPool
        self.assetStore = assetStore
        startObserving()
        Task { [weak self] in await self?.backfillPending() }
    }

    private func startObserving() {
        let items = ValueObservation.tracking { db in
            try Item.order(Column("createdAt").desc).limit(400).fetchAll(db)
        }
        itemsCancellable = items.start(
            in: dbPool,
            scheduling: .immediate,
            onError: { error in NSLog("Aura: item observation error: \(error)") },
            onChange: { [weak self] items in
                guard let self else { return }
                self.libraryItems = items
                self.recentItems = Array(items.prefix(40))
            }
        )

        let collections = ValueObservation.tracking { db in
            try ItemCollection.order(Column("sortOrder"), Column("createdAt")).fetchAll(db)
        }
        collectionsCancellable = collections.start(
            in: dbPool,
            scheduling: .immediate,
            onError: { error in NSLog("Aura: collection observation error: \(error)") },
            onChange: { [weak self] collections in self?.collections = collections }
        )
    }

    // MARK: - Collections

    func createCollection(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (collections.map(\.sortOrder).max() ?? 0) + 1
        let collection = ItemCollection(id: UUID().uuidString, name: trimmed, kind: "user",
                                    symbol: "folder", sortOrder: nextOrder, createdAt: Date())
        Task { try? await dbPool.write { db in try collection.insert(db) } }
    }

    func renameCollection(_ collection: ItemCollection, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = collection
        updated.name = trimmed
        let toSave = updated
        Task { try? await dbPool.write { db in try toSave.update(db) } }
    }

    func deleteCollection(_ collection: ItemCollection) {
        let id = collection.id
        Task {
            try? await dbPool.write { db in
                try db.execute(sql: "UPDATE item SET collectionId = NULL WHERE collectionId = ?", arguments: [id])
                _ = try ItemCollection.deleteOne(db, key: id)
            }
        }
    }

    func setCollection(_ item: Item, to collectionId: String?) {
        var updated = item
        updated.collectionId = collectionId
        updated.updatedAt = Date()
        let toSave = updated
        Task { try? await dbPool.write { db in try toSave.update(db) } }
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
            switch item.itemType {
            case .url: Task { [weak self] in await self?.enrichLink(item) }
            case .file: Task { [weak self] in await self?.enrichFile(item) }
            default: break
            }
        } catch {
            NSLog("Aura: save failed: \(error)")
        }
    }

    // MARK: - Rich link previews

    /// Fetches Open Graph / YouTube metadata for a saved URL and updates the row
    /// in place (the card upgrades live via ValueObservation). Runs after the
    /// item is already saved, so the network fetch never blocks the save.
    func enrichLink(_ item: Item) async {
        guard item.itemType == .url,
              let urlString = item.textContent,
              let url = URL(string: urlString) else { return }

        let meta = await LinkMetadataService.fetch(url: url)

        var updated = item
        if let imageData = meta.imageData {
            // Downsample the hero image so cards stay light.
            let toStore = ThumbnailService.make(fromImageData: imageData)?.data ?? imageData
            if let stored = try? assetStore.storeImage(toStore, subdir: "og") {
                updated.ogImagePath = stored.relativePath
            }
        }
        if let iconData = meta.iconData,
           let stored = try? assetStore.storeImage(iconData, subdir: "favicon") {
            updated.faviconPath = stored.relativePath
        }
        if let description = meta.description { updated.ogDescription = description }
        // Always set ogTitle (falling back to host) so this item is marked
        // enriched and the backfill won't keep re-fetching it.
        let resolvedTitle = meta.title ?? updated.host ?? urlString
        updated.ogTitle = resolvedTitle
        updated.title = resolvedTitle
        updated.updatedAt = Date()

        let toSave = updated
        try? await dbPool.write { db in try toSave.update(db) }
    }

    /// Generates a Quick Look thumbnail for a saved (non-image) file and stores
    /// it inline so the card upgrades from a generic icon to a real preview.
    func enrichFile(_ item: Item) async {
        guard item.itemType == .file, let path = item.assetPath else { return }
        let url = assetStore.absoluteURL(for: path)

        var updated = item
        if let thumb = await FileThumbnailService.make(forFileURL: url) {
            updated.thumbnail = thumb.data
            updated.thumbWidth = thumb.width
            updated.thumbHeight = thumb.height
        }
        // ogTitle is unused for files — use it as a "processed" marker so the
        // backfill doesn't retry files that have no Quick Look thumbnail.
        updated.ogTitle = item.fileName ?? item.title ?? "file"
        updated.updatedAt = Date()

        let toSave = updated
        try? await dbPool.write { db in try toSave.update(db) }
    }

    /// Enriches any previously-saved links or files that were never processed.
    private func backfillPending() async {
        let pending: [Item] = (try? await dbPool.read { db in
            try Item
                .filter([ItemType.url.rawValue, ItemType.file.rawValue].contains(Column("type"))
                        && Column("ogTitle") == nil)
                .order(Column("createdAt").desc)
                .limit(40)
                .fetchAll(db)
        }) ?? []
        for item in pending {
            switch item.itemType {
            case .url: await enrichLink(item)
            case .file: await enrichFile(item)
            default: break
            }
        }
    }

    /// Resolves a stored relative asset path (og image, favicon, …) to a URL.
    func fileURL(forRelativePath path: String?) -> URL? {
        guard let path else { return nil }
        return assetStore.absoluteURL(for: path)
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

    /// What a primary click does: open links/files/images in their default
    /// app or browser; text & colors have nothing to open, so they copy.
    func primaryAction(_ item: Item) {
        open(item)
    }

    func open(_ item: Item) {
        switch item.itemType {
        case .url:
            if let url = item.textContent.flatMap({ URL(string: $0) }) {
                NSWorkspace.shared.open(url)
            }
        case .file, .image:
            if let url = assetURL(for: item) {
                NSWorkspace.shared.open(url)
            }
        case .text, .color:
            copyToClipboard(item)
        }
    }

    func revealInFinder(_ item: Item) {
        guard let url = assetURL(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
