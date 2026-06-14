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
    private let semanticIndex: SemanticIndex

    private(set) var libraryItems: [Item] = []
    private(set) var recentItems: [Item] = []
    private(set) var collections: [ItemCollection] = []

    /// Called whenever we write to the pasteboard ourselves, so the clipboard
    /// watcher can ignore that change and avoid nudging our own copy-back.
    var onSelfCopy: ((Int) -> Void)?

    @ObservationIgnored private var itemsCancellable: AnyDatabaseCancellable?
    @ObservationIgnored private var collectionsCancellable: AnyDatabaseCancellable?

    /// Strictly-increasing stamp for X-bookmark saves so each new sync lands
    /// above the previous one (the library orders by `createdAt` desc).
    @ObservationIgnored private var lastXStamp = Date.distantPast

    init(dbPool: DatabasePool, assetStore: AssetStore) {
        self.dbPool = dbPool
        self.assetStore = assetStore
        self.semanticIndex = SemanticIndex(dbPool: dbPool)
        startObserving()
        Task { [weak self] in
            await self?.semanticIndex.reload()
            await self?.backfillPending()
            await self?.backfillSearchIndex()
            await self?.backfillImageLabels()
        }
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
            // A "link + note" capture stays text but carries link metadata so it
            // also shows under Links and renders an embed.
            if let url = CaptureCandidate.firstWebURL(in: string) {
                item.host = url.host
                item.urlSubtype = URLClassifier.subtype(for: url).rawValue
            }

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
            // Enrich for previews first, THEN mine + embed for search so the
            // corpus includes any title/description the enrichment fetched.
            switch item.itemType {
            case .url, .text where item.linkURL != nil:
                Task { [weak self] in
                    await self?.enrichLink(item)
                    await self?.enrichForSearch(itemID: item.id)
                }
            case .file:
                Task { [weak self] in
                    await self?.enrichFile(item)
                    await self?.enrichForSearch(itemID: item.id)
                }
            default:
                Task { [weak self] in await self?.enrichForSearch(itemID: item.id) }
            }
        } catch {
            NSLog("Aura: save failed: \(error)")
        }
    }

    /// Saves a brand-new text note authored in-app (the Library composer) or the
    /// notch. Mirrors the `.text` branch of `save()` for title + embedded-link
    /// metadata. The `sourceApp` marker is what routes the note to the Notes tab.
    func saveNote(text: String, sourceApp: String? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var item = Item(type: .text)
        item.textContent = trimmed
        item.title = Self.titleSnippet(from: trimmed)
        item.sourceApp = sourceApp
        if let url = CaptureCandidate.firstWebURL(in: trimmed) {
            item.host = url.host
            item.urlSubtype = URLClassifier.subtype(for: url).rawValue
        }

        let toInsert = item
        do {
            try await dbPool.write { db in try toInsert.insert(db) }
            // Link-bearing notes enrich their preview before the search pass so
            // the corpus includes any fetched title/description (mirrors save()).
            if toInsert.linkURL != nil {
                Task { [weak self] in
                    await self?.enrichLink(toInsert)
                    await self?.enrichForSearch(itemID: toInsert.id)
                }
            } else {
                Task { [weak self] in await self?.enrichForSearch(itemID: toInsert.id) }
            }
        } catch {
            NSLog("Aura: saveNote failed: \(error)")
        }
    }

    /// Applies a composer edit to a `.text` item: updates the text, recomputing
    /// the title + embedded-link metadata exactly as `save()` does, then
    /// re-enriches link preview + search. No-op for non-text items.
    func updateNote(_ item: Item, text: String) async {
        guard item.itemType == .text else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = item
        updated.textContent = trimmed
        updated.title = Self.titleSnippet(from: trimmed)

        // An edit can add, change, or remove the embedded URL — re-derive from
        // scratch, clearing the cached link preview when the URL goes away.
        let newURL = CaptureCandidate.firstWebURL(in: trimmed)
        let oldURL = item.linkURL
        if let url = newURL {
            updated.host = url.host
            updated.urlSubtype = URLClassifier.subtype(for: url).rawValue
        } else {
            updated.host = nil
            updated.urlSubtype = nil
            updated.ogTitle = nil
            updated.ogDescription = nil
            updated.ogImagePath = nil
            updated.faviconPath = nil
        }
        updated.updatedAt = Date()

        let toSave = updated
        try? await dbPool.write { db in try toSave.update(db) }

        if newURL != nil, newURL != oldURL { await enrichLink(toSave) }
        await enrichForSearch(itemID: toSave.id)
    }

    // MARK: - Rich link previews

    /// Fetches Open Graph / YouTube metadata for a saved URL — or the URL
    /// embedded in a "link + note" text capture — and updates the row in place
    /// (the card upgrades live via ValueObservation). Runs after the item is
    /// already saved, so the network fetch never blocks the save.
    func enrichLink(_ item: Item) async {
        // Respect the "fetch link previews" setting (the only networked feature).
        guard UserDefaults.standard.object(forKey: "linkPreviewsEnabled") as? Bool ?? true else { return }
        guard let url = item.linkURL else { return }

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
        let resolvedTitle = meta.title ?? updated.host ?? url.host ?? url.absoluteString
        updated.ogTitle = resolvedTitle
        // Text captures keep their snippet title; the embed shows ogTitle.
        if item.itemType == .url { updated.title = resolvedTitle }
        if updated.host == nil { updated.host = url.host }
        if updated.urlSubtype == nil { updated.urlSubtype = URLClassifier.subtype(for: url).rawValue }
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

    // MARK: - Search enrichment (extracted text + embedding)

    /// Mines an item's content into `extractedText` (image OCR, link article
    /// body, PDF text), folds the whole corpus into a dense embedding, and
    /// stores the vector — so the item becomes findable by meaning, not just
    /// keywords. Re-fetches the item first so it sees fields written by
    /// `enrichLink`/`enrichFile`, and updates only the `extractedText` column to
    /// avoid clobbering those concurrent writers.
    /// Bump when enrichment gains a new extractor, so already-embedded items
    /// get re-enriched once by the matching backfill (stamped in sourceHash).
    static let enrichVersion = "enrich-v2"   // v2 = OCR + image classification

    func enrichForSearch(itemID: String) async {
        guard let item = try? await dbPool.read({ db in try Item.fetchOne(db, key: itemID) }) else { return }

        let extracted = await extractText(for: item)
        if let extracted, !extracted.isEmpty {
            let now = Date()
            try? await dbPool.write { db in
                try db.execute(sql: "UPDATE item SET extractedText = ?, updatedAt = ? WHERE id = ?",
                               arguments: [extracted, now, itemID])
            }
        }

        // Build the corpus from the (possibly updated) item and embed it. If
        // assets aren't downloaded yet, embed returns nil and the backfill will
        // pick this item up on a later launch.
        var enriched = item
        if let extracted, !extracted.isEmpty { enriched.extractedText = extracted }
        guard let vector = await EmbeddingService.shared.embed(enriched.searchText) else { return }

        let record = EmbeddingRecord(itemId: itemID, vector: vector,
                                     model: EmbeddingService.modelIdentifier,
                                     sourceHash: Self.enrichVersion)
        try? await dbPool.write { db in try record.save(db) }
        await semanticIndex.upsert(itemId: itemID, vector: vector)
    }

    /// Type-specific text extraction. The synchronous, CPU-bound extractors are
    /// offloaded off the main actor; the link path is already non-isolated.
    private func extractText(for item: Item) async -> String? {
        switch item.itemType {
        case .image:
            guard let path = item.assetPath else { return nil }
            let url = assetStore.absoluteURL(for: path)
            // Two extractors: OCR reads the text IN the image (screenshots,
            // memes); classification names what the image IS (dog, beach,
            // food), so photos without any text become searchable too.
            return await Task.detached {
                let ocr = OCRService.recognizeText(in: url)
                let labels = ImageClassifierService.labels(for: url)
                var parts: [String] = []
                if let ocr { parts.append(ocr) }
                if let labels { parts.append("Looks like: \(labels)") }
                return parts.isEmpty ? nil : parts.joined(separator: "\n")
            }.value

        case .file:
            guard let path = item.assetPath else { return nil }
            let isPDF = item.uti == "com.adobe.pdf" || (item.fileName?.lowercased().hasSuffix(".pdf") ?? false)
            guard isPDF else { return nil }
            let url = assetStore.absoluteURL(for: path)
            return await Task.detached { PDFTextExtractor.extractText(from: url) }.value

        case .url, .text:
            guard UserDefaults.standard.object(forKey: "linkPreviewsEnabled") as? Bool ?? true,
                  let url = item.linkURL else { return nil }
            return await LinkMetadataService.fetchArticleText(url: url)

        case .color:
            return nil
        }
    }

    /// Enriches any previously-saved links, files, or link-bearing text
    /// captures that were never processed.
    private func backfillPending() async {
        let pending: [Item] = (try? await dbPool.read { db in
            try Item
                .filter(Column("ogTitle") == nil
                        && ([ItemType.url.rawValue, ItemType.file.rawValue].contains(Column("type"))
                            || (Column("type") == ItemType.text.rawValue
                                && Column("textContent").like("%http%"))))
                .order(Column("createdAt").desc)
                .limit(40)
                .fetchAll(db)
        }) ?? []
        for item in pending {
            switch item.itemType {
            case .url: await enrichLink(item)
            case .text where item.linkURL != nil: await enrichLink(item)
            case .file: await enrichFile(item)
            default: break
            }
        }
    }

    /// One-time index build for items captured before semantic search existed:
    /// embed whatever text they already have (title / content / link metadata).
    /// Cheap — no network or OCR — so it covers a large batch per launch;
    /// freshly-captured items are fully enriched live by `enrichForSearch`.
    private func backfillSearchIndex() async {
        let pending: [Item] = (try? await dbPool.read { db in
            try Item
                .filter(sql: "id NOT IN (SELECT itemId FROM embedding)")
                .order(Column("createdAt").desc)
                .limit(200)
                .fetchAll(db)
        }) ?? []
        guard !pending.isEmpty else { return }
        for item in pending {
            guard let vector = await EmbeddingService.shared.embed(item.searchText) else { continue }
            // sourceHash stays nil: this cheap pass runs no extractors, so the
            // image-label backfill below still owes these items a full pass.
            let record = EmbeddingRecord(itemId: item.id, vector: vector,
                                         model: EmbeddingService.modelIdentifier, sourceHash: nil)
            try? await dbPool.write { db in try record.save(db) }
        }
        await semanticIndex.reload()
    }

    /// One-time re-enrichment of images embedded before classification existed
    /// (sourceHash missing or from an older enrich generation). enrichForSearch
    /// rewrites extractedText (OCR + labels), re-embeds, and stamps the current
    /// version — so each image is touched once, ever. ~50–150 ms per image,
    /// capped per launch so a big vault spreads over a few launches.
    private func backfillImageLabels() async {
        let stale: [String] = (try? await dbPool.read { db in
            try String.fetchAll(db, sql: """
                SELECT item.id FROM item
                JOIN embedding ON embedding.itemId = item.id
                WHERE item.type = 'image'
                  AND (embedding.sourceHash IS NULL OR embedding.sourceHash <> ?)
                ORDER BY item.createdAt DESC
                LIMIT 100
                """, arguments: [Self.enrichVersion])
        }) ?? []
        guard !stale.isEmpty else { return }
        for id in stale { await enrichForSearch(itemID: id) }
        await semanticIndex.reload()
    }

    /// Resolves a stored relative asset path (og image, favicon, …) to a URL.
    func fileURL(forRelativePath path: String?) -> URL? {
        guard let path else { return nil }
        return assetStore.absoluteURL(for: path)
    }

    // MARK: - Search

    /// Hybrid natural-language search: FTS5 keyword matching fused with semantic
    /// vector similarity (see `HybridSearch`), ordered best-match-first. Empty
    /// query returns the current library.
    func search(_ query: String) async -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return libraryItems }
        let hybrid = HybridSearch(dbPool: dbPool, semanticIndex: semanticIndex)
        return await hybrid.search(trimmed)
    }

    /// Whether the on-device conversational answer layer can run on this Mac
    /// (macOS 26+ / Apple Silicon / Apple Intelligence on). The UI uses this to
    /// decide whether to show the answer banner.
    var canAnswer: Bool { AnswerService.isAvailable }

    /// Stream a written answer to `query`, grounded in `items` (the current
    /// search results). Yields nothing when unavailable — see `AnswerService`.
    func answer(to query: String, from items: [Item]) -> AsyncStream<String> {
        AnswerService.streamAnswer(query: query, items: items)
    }

    // MARK: - Bulk

    /// Exports the entire vault to a zip of one-file-per-item, returning the URL
    /// of a temporary `.zip`. The caller moves it to the user's chosen location.
    /// Reads every item directly (not the 400-row `libraryItems` cap).
    func exportVaultZip() async throws -> URL {
        let exporter = VaultExporter(dbPool: dbPool, assetStore: assetStore)
        return try await exporter.export()
    }

    /// Imports a browser's exported bookmarks (`.html`, Netscape format) as `url`
    /// items, preserving their original dates and skipping URLs already saved.
    /// Items land instantly (host + any embedded favicon); link previews are then
    /// fetched by a throttled background pass.
    func importBookmarks(from fileURL: URL) async throws -> BookmarkImporter.ImportResult {
        let importer = BookmarkImporter(dbPool: dbPool, assetStore: assetStore)
        let (result, newIDs) = try await importer.run(fileURL: fileURL)
        enrichImportedBookmarks(ids: newIDs)
        return result
    }

    /// Fetches link previews for freshly-imported bookmarks with a sliding window
    /// of a few concurrent requests — polite to remote hosts, and far faster than
    /// the serial 40-per-launch `backfillPending`. Anything not reached (app quit
    /// mid-pass) stays `ogTitle == nil`, so the backfill still finishes it later.
    private func enrichImportedBookmarks(ids: [String]) {
        guard UserDefaults.standard.object(forKey: "linkPreviewsEnabled") as? Bool ?? true else { return }
        guard !ids.isEmpty else { return }
        Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                let maxConcurrent = 4
                var index = 0
                while index < min(maxConcurrent, ids.count) {
                    let id = ids[index]; index += 1
                    group.addTask { [weak self] in await self?.enrichImported(id: id) }
                }
                while await group.next() != nil {
                    guard index < ids.count else { continue }
                    let id = ids[index]; index += 1
                    group.addTask { [weak self] in await self?.enrichImported(id: id) }
                }
            }
        }
    }

    private func enrichImported(id: String) async {
        guard let item = try? await dbPool.read({ db in try Item.fetchOne(db, key: id) }) else { return }
        await enrichLink(item)
    }

    /// Deletes every saved item and its on-disk assets (collections are kept).
    func deleteAllItems() {
        let assetStore = self.assetStore
        let semanticIndex = self.semanticIndex
        Task {
            do {
                // Embedding rows cascade-delete with their items (foreign key);
                // reload the in-memory index so search reflects the empty vault.
                try await dbPool.write { db in _ = try Item.deleteAll(db) }
                assetStore.removeAllAssets()
                await semanticIndex.reload()
            } catch {
                NSLog("Aura: clear-all failed: \(error)")
            }
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

    /// What a primary click does: open links/files/images in their default
    /// app or browser; text & colors have nothing to open, so they copy.
    func primaryAction(_ item: Item) {
        open(item)
    }

    func open(_ item: Item) {
        switch item.itemType {
        case .url:
            if let url = item.linkURL {
                NSWorkspace.shared.open(url)
            }
        case .file, .image:
            if let url = assetURL(for: item) {
                NSWorkspace.shared.open(url)
            }
        case .text:
            // A "link + note" capture opens its embedded link; plain text copies.
            if let url = item.linkURL {
                NSWorkspace.shared.open(url)
            } else {
                copyToClipboard(item)
            }
        case .color:
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
        let semanticIndex = self.semanticIndex
        Task {
            do {
                // The embedding row cascade-deletes with the item; drop it from
                // the in-memory index too so it stops appearing in results.
                try await dbPool.write { db in
                    _ = try Item.deleteOne(db, key: id)
                }
                if let assetPath { assetStore.removeAsset(relativePath: assetPath) }
                await semanticIndex.remove(itemId: id)
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

// MARK: - X (Twitter) bookmark sync

extension DataStore {
    /// Saves one bookmarked tweet as a `.url` item, deduped by status id.
    /// Inserts the text immediately (so it appears live) and downloads the
    /// hero image + author avatar in the background, mirroring `enrichLink`.
    func saveXTweet(_ tweet: XTweet) async -> XSaveOutcome {
        guard let statusId = tweet.statusId, !tweet.tweetUrl.isEmpty else {
            return XSaveOutcome(ok: false, duplicate: false)
        }
        if await xTweetExists(statusId: statusId) {
            return XSaveOutcome(ok: true, duplicate: true)
        }

        // Bulk import supplies its own descending timestamp (newest on top);
        // single saves (click/forward) stamp monotonically at import time.
        let item = XBookmarkMapper.makeItem(from: tweet, createdAt: tweet.createdAt ?? nextXStamp())
        do {
            try await dbPool.write { db in try item.insert(db) }
        } catch {
            NSLog("Aura: X bookmark insert failed: \(error)")
            return XSaveOutcome(ok: false, duplicate: false)
        }
        enrichXItem(id: item.id, imageURL: tweet.bestImageURL, avatarURL: tweet.authorAvatarUrl)
        return XSaveOutcome(ok: true, duplicate: false)
    }

    /// True when a `.url` item already points at this tweet (matches the
    /// permalink's `/status/<id>` suffix, optionally followed by a query).
    private func xTweetExists(statusId: String) async -> Bool {
        let endsWith = "%/status/\(statusId)"
        let withQuery = "%/status/\(statusId)?%"
        return (try? await dbPool.read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM item WHERE type = ? AND (textContent LIKE ? OR textContent LIKE ?)",
                arguments: [ItemType.url.rawValue, endsWith, withQuery]) ?? 0
            return count > 0
        }) ?? false
    }

    /// Monotonic import-time stamp: each save gets a `createdAt` strictly newer
    /// than the last, so a burst of synced bookmarks keeps a stable top order.
    private func nextXStamp() -> Date {
        let now = Date()
        let stamp = now > lastXStamp ? now : lastXStamp.addingTimeInterval(0.001)
        lastXStamp = stamp
        return stamp
    }

    /// Downloads the tweet's image + avatar off the main actor and updates the
    /// row in place (the grid upgrades live via the item observation).
    private func enrichXItem(id: String, imageURL: String?, avatarURL: String?) {
        let assetStore = self.assetStore
        let dbPool = self.dbPool
        Task.detached(priority: .utility) {
            var imageData: Data?
            var iconData: Data?
            if let imageURL, let url = URL(string: imageURL) { imageData = await DataStore.downloadData(from: url) }
            if let avatarURL, let url = URL(string: avatarURL) { iconData = await DataStore.downloadData(from: url) }
            guard imageData != nil || iconData != nil else { return }

            guard var item = try? await dbPool.read({ db in try Item.fetchOne(db, key: id) }) else { return }
            if let imageData {
                let toStore = ThumbnailService.make(fromImageData: imageData)?.data ?? imageData
                if let stored = try? assetStore.storeImage(toStore, subdir: "og") {
                    item.ogImagePath = stored.relativePath
                }
            }
            if let iconData, let stored = try? assetStore.storeImage(iconData, subdir: "favicon") {
                item.faviconPath = stored.relativePath
            }
            item.updatedAt = Date()
            try? await dbPool.write { db in try item.update(db) }
        }
    }

    private static func downloadData(from url: URL, maxBytes: Int = 8 * 1024 * 1024) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Aura",
                         forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            return data.count <= maxBytes ? data : nil
        } catch {
            return nil
        }
    }
}
