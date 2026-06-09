import Foundation
import GRDB

/// Bridges "open the library window" from AppKit (the notch) to SwiftUI's
/// scene-based `openWindow`. A scene view (the menu-bar label) fills in `open`
/// at launch; the notch just calls it.
@MainActor
final class LibraryLauncher {
    var open: (() -> Void)?
}

/// Dependency-injection root: builds the database, store, and services once and
/// shares the single `DataStore` instance across both surfaces.
@MainActor
final class AppEnvironment {
    let assetStore: AssetStore
    let dbPool: DatabasePool
    let dataStore: DataStore
    let clipboardWatcher: ClipboardWatcher
    let libraryLauncher = LibraryLauncher()

    init() {
        do {
            let assetStore = try AssetStore()
            let dbPool = try AppDatabase.open()
            self.assetStore = assetStore
            self.dbPool = dbPool
            self.dataStore = DataStore(dbPool: dbPool, assetStore: assetStore)
            self.clipboardWatcher = ClipboardWatcher()
        } catch {
            fatalError("Aura failed to initialize storage: \(error)")
        }
    }
}
