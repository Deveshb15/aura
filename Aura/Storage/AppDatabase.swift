import Foundation
import GRDB

/// Opens the on-disk SQLite database and owns the schema migrations.
enum AppDatabase {

    /// `~/Library/Application Support/Aura/`
    static func supportDirectory() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
        let dir = appSupport.appendingPathComponent("Aura", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func open() throws -> DatabasePool {
        let dbURL = try supportDirectory().appendingPathComponent("aura.sqlite")
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: dbURL.path, configuration: config)
        try migrator.migrate(pool)
        return pool
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        // During development, rebuild the schema if it changes rather than
        // forcing manual migrations. Remove before any real release.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "collection") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("symbol", .text)
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "item") { t in
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("textContent", .text)
                t.column("title", .text)
                t.column("urlSubtype", .text)
                t.column("sourceApp", .text)
                t.column("sourceURL", .text)
                t.column("assetPath", .text)
                t.column("fileName", .text)
                t.column("uti", .text)
                t.column("byteSize", .integer)
                t.column("thumbnail", .blob)
                t.column("thumbWidth", .integer)
                t.column("thumbHeight", .integer)
                t.column("ogTitle", .text)
                t.column("ogDescription", .text)
                t.column("ogImagePath", .text)
                t.column("faviconPath", .text)
                t.column("host", .text)
                t.column("colorHex", .text)
                t.column("collectionId", .text)
            }
            try db.create(index: "item_on_createdAt", on: "item", columns: ["createdAt"])
            try db.create(index: "item_on_type", on: "item", columns: ["type"])

            // Full-text search mirror of `item`, kept in sync by GRDB-generated triggers.
            try db.create(virtualTable: "item_fts", using: FTS5()) { t in
                t.synchronize(withTable: "item")
                t.column("title")
                t.column("textContent")
                t.column("ogTitle")
                t.column("ogDescription")
                t.column("host")
                t.column("fileName")
            }

            // Seed built-in collections / tabs.
            let builtins: [(String, String)] = [
                ("History", "clock"),
                ("Prompts", "text.bubble"),
                ("Colors", "paintpalette"),
                ("Assets", "photo"),
                ("Inspirations", "sparkles"),
            ]
            for (index, entry) in builtins.enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO collection (id, name, kind, symbol, sortOrder, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [UUID().uuidString, entry.0, "builtin", entry.1, index, Date()])
            }
        }

        // Collections become real (user-managed) tabs in Phase 5. Drop the
        // built-ins that are redundant with "All" or imply smart type-filters,
        // leaving Prompts + Inspirations as friendly starter collections.
        migrator.registerMigration("v2-prune-builtins") { db in
            try db.execute(sql: """
                DELETE FROM collection
                WHERE kind = 'builtin' AND name IN ('History', 'Colors', 'Assets')
                """)
        }

        // Semantic search: mine each item's content into `extractedText`
        // (image OCR, link article body, video description, PDF text), fold it
        // into the FTS5 index, and store a dense embedding vector per item.
        migrator.registerMigration("v3-semantic-search") { db in
            // 1. New searchable-text column on the main table.
            try db.alter(table: "item") { t in
                t.add(column: "extractedText", .text)
            }

            // 2. Rebuild the FTS5 mirror to also index `extractedText`. Drop the
            //    old virtual table and its synchronization triggers, then
            //    recreate — `synchronize` repopulates from existing rows and
            //    reinstalls the triggers.
            try db.drop(table: "item_fts")
            try db.dropFTS5SynchronizationTriggers(forTable: "item_fts")
            try db.create(virtualTable: "item_fts", using: FTS5()) { t in
                t.synchronize(withTable: "item")
                t.column("title")
                t.column("textContent")
                t.column("ogTitle")
                t.column("ogDescription")
                t.column("host")
                t.column("fileName")
                t.column("extractedText")
            }

            // 3. One dense vector per item for semantic (cosine) retrieval.
            //    Kept in its own table so a future swap to sqlite-vec stays
            //    surgical; ON DELETE CASCADE (with PRAGMA foreign_keys=ON)
            //    drops the vector when its item is deleted.
            try db.create(table: "embedding") { t in
                t.column("itemId", .text).primaryKey()
                    .references("item", onDelete: .cascade)
                t.column("vector", .blob).notNull()
                t.column("model", .text).notNull()
                t.column("dims", .integer).notNull()
                t.column("sourceHash", .text)
                t.column("updatedAt", .datetime).notNull()
            }
        }

        return migrator
    }
}
