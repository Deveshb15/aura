import Foundation
import GRDB

/// Dependency-injection root: builds the database, store, and services once and
/// shares the single `DataStore` instance across both surfaces.
@MainActor
final class AppEnvironment {
    let assetStore: AssetStore
    let dbPool: DatabasePool
    let dataStore: DataStore
    let clipboardWatcher: ClipboardWatcher

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
