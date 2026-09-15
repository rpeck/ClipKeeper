import Foundation
import GRDB

/// Owns the SQLite database and its schema.
final class Database {
    let queue: DatabaseQueue

    /// Directory that holds the database and the blob store.
    static var supportDirectory: URL {
        // CLIPKEEPER_DATA_DIR points the app at another data folder, for tests and demos.
        if let override = ProcessInfo.processInfo.environment["CLIPKEEPER_DATA_DIR"], !override.isEmpty {
            let dir = URL(fileURLWithPath: override, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ClipKeeper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Opens (or creates) the database at the standard location.
    static func open() throws -> Database {
        let dir = supportDirectory
        let url = dir.appendingPathComponent("clipkeeper.sqlite")
        let db = try Database(path: url.path)
        restrictPermissions(directory: dir)
        return db
    }

    /// Makes the data folder private to this user: folders 700, files 600.
    static func restrictPermissions(directory: URL) {
        let fm = FileManager.default
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            try? fm.setAttributes([.posixPermissions: isDir ? 0o700 : 0o600], ofItemAtPath: url.path)
        }
    }

    /// Opens an in-memory database. Used by tests.
    static func inMemory() throws -> Database {
        try Database(path: nil)
    }

    private init(path: String?) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        // Deleted rows are overwritten with zeros inside the database file, so
        // a deleted clip does not linger in free pages.
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        if let path {
            queue = try DatabaseQueue(path: path, configuration: config)
        } else {
            queue = try DatabaseQueue(configuration: config)
        }
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "collection") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "clip") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("updatedAt", .datetime).notNull()
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("text", .text).notNull()
                t.column("contentHash", .text).notNull().indexed()
                t.column("byteCount", .integer).notNull()
                t.column("sourceBundleID", .text)
                t.column("sourceAppName", .text)
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("collectionID", .text).indexed()
                t.column("position", .double).notNull().defaults(to: 0)
                t.column("language", .text)
                t.column("imageWidth", .integer)
                t.column("imageHeight", .integer)
                t.column("linkTitle", .text)
                t.column("linkHost", .text)
                t.column("lineCount", .integer).notNull().defaults(to: 0)
                t.column("charCount", .integer).notNull().defaults(to: 0)
                t.column("hasRich", .boolean).notNull().defaults(to: false)
                t.column("colorHex", .text)
            }
            try db.create(virtualTable: "clip_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clip")
                t.tokenizer = .unicode61()
                t.column("title")
                t.column("text")
                t.column("sourceAppName")
                t.column("linkTitle")
            }
        }
        migrator.registerMigration("v2-formats") { db in
            try db.alter(table: "clip") { t in
                t.add(column: "formats", .text)
            }
        }
        try migrator.migrate(queue)
    }
}
