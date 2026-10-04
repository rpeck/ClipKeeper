import AppKit
import Foundation
import GRDB

/// The store: every read and write of clips and collections goes through here.
@MainActor
final class ClipStore: ObservableObject {
    let database: Database
    let blobs: BlobStore
    let prefs: Preferences

    @Published private(set) var collections: [ClipCollection] = []
    /// Bumps after every change. Views reload when it changes.
    @Published private(set) var changeToken: Int = 0

    private var linkTasks: [String: Task<Void, Never>] = [:]

    init(database: Database, blobs: BlobStore, prefs: Preferences = .shared) {
        self.database = database
        self.blobs = blobs
        self.prefs = prefs
        reloadCollections()
    }

    private var db: DatabaseQueue { database.queue }

    private func bump() { changeToken &+= 1 }

    // MARK: Sets

    var sets: [ClipSet] { [.history] + collections.map { .collection($0) } }

    func reloadCollections() {
        collections = (try? db.read { db in
            try ClipCollection.order(ClipCollection.Columns.sortOrder, Column("createdAt")).fetchAll(db)
        }) ?? []
    }

    @discardableResult
    func createCollection(named name: String) -> ClipCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var c = ClipCollection(id: nil, uuid: UUID().uuidString, name: trimmed, sortOrder: (collections.map(\.sortOrder).max() ?? 0) + 1, createdAt: Date())
        do {
            try db.write { db in try c.insert(db) }
            reloadCollections()
            bump()
            return c
        } catch {
            NSLog("createCollection failed: \(error)")
            return nil
        }
    }

    func renameCollection(_ collection: ClipCollection, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? db.write { db in
            try db.execute(sql: "UPDATE collection SET name = ? WHERE uuid = ?", arguments: [trimmed, collection.uuid])
        }
        reloadCollections()
        bump()
    }

    /// Deletes a collection. Its clips move back to History.
    func deleteCollection(_ collection: ClipCollection) {
        try? db.write { db in
            try db.execute(sql: "UPDATE clip SET collectionID = NULL, updatedAt = ? WHERE collectionID = ?", arguments: [Date(), collection.uuid])
            try db.execute(sql: "DELETE FROM collection WHERE uuid = ?", arguments: [collection.uuid])
        }
        reloadCollections()
        bump()
    }

    func moveCollection(_ collection: ClipCollection, toIndex index: Int) {
        var list = collections
        guard let from = list.firstIndex(of: collection) else { return }
        let item = list.remove(at: from)
        list.insert(item, at: max(0, min(index, list.count)))
        try? db.write { db in
            for (i, c) in list.enumerated() {
                try db.execute(sql: "UPDATE collection SET sortOrder = ? WHERE uuid = ?", arguments: [i, c.uuid])
            }
        }
        reloadCollections()
        bump()
    }

    // MARK: Reading clips

    /// Clips in a set, newest first, pinned first. `query` filters with full-text
    /// search, ranked by match quality unless `newestFirst` is set.
    func clips(in set: ClipSet, query: String, newestFirst: Bool = false) -> [Clip] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return (try? db.read { db -> [Clip] in
            let collectionClause = set.collectionID == nil ? "clip.collectionID IS NULL" : "clip.collectionID = ?"
            var args: [DatabaseValueConvertible] = []
            if let cid = set.collectionID { args.append(cid) }
            let order = "clip.pinned DESC, clip.position DESC, clip.id DESC"
            if q.isEmpty {
                return try Clip.fetchAll(db, sql: "SELECT clip.* FROM clip WHERE \(collectionClause) ORDER BY \(order) LIMIT 2000", arguments: StatementArguments(args))
            }
            if let pattern = FTS5Pattern(matchingAllPrefixesIn: q) {
                let rank = newestFirst ? order : "clip.pinned DESC, bm25(clip_fts, 4.0, 1.0, 2.0, 3.0), clip.position DESC, clip.id DESC"
                let sql = "SELECT clip.* FROM clip JOIN clip_fts ON clip_fts.rowid = clip.id WHERE clip_fts MATCH ? AND \(collectionClause) ORDER BY \(rank) LIMIT 500"
                return try Clip.fetchAll(db, sql: sql, arguments: StatementArguments([pattern] + args))
            }
            let like = "%" + q + "%"
            return try Clip.fetchAll(db, sql: "SELECT clip.* FROM clip WHERE (clip.text LIKE ? OR clip.title LIKE ?) AND \(collectionClause) ORDER BY \(order) LIMIT 500", arguments: StatementArguments([like, like] + args))
        }) ?? []
    }

    func clip(uuid: String) -> Clip? {
        try? db.read { db in try Clip.filter(Clip.Columns.uuid == uuid).fetchOne(db) }
    }

    func snapshot(for clip: Clip) -> PasteboardSnapshot? {
        blobs.loadSnapshot(for: clip.uuid)
    }

    func historyCount() -> Int {
        (try? db.read { db in try Clip.filter(Clip.Columns.collectionID == nil).fetchCount(db) }) ?? 0
    }

    func totalCount() -> Int {
        (try? db.read { db in try Clip.fetchCount(db) }) ?? 0
    }

    // MARK: Ingest

    /// Stores a new capture. Returns the stored clip, or nil when the content is
    /// empty or unsupported. A duplicate of a History clip moves it to the top.
    @discardableResult
    func ingest(_ snapshot: PasteboardSnapshot, sourceBundleID: String?, sourceAppName: String?, title titleOverride: String? = nil, sourcePath: String? = nil) -> Clip? {
        let t0 = Date()
        guard let c = ContentClassifier.classify(snapshot) else { return nil }
        if PasteboardMonitor.debug { NSLog("  classified as %@ in %.0f ms", c.kind.rawValue, Date().timeIntervalSince(t0) * 1000) }
        let now = Date()

        // Duplicate in History: move to top, refresh the snapshot.
        if let existing = try? db.read({ db in
            try Clip.filter(Clip.Columns.contentHash == c.contentHash).filter(Clip.Columns.collectionID == nil).fetchOne(db)
        }) {
            var updated = existing
            updated.createdAt = now
            updated.updatedAt = now
            updated.position = now.timeIntervalSince1970
            updated.sourceBundleID = sourceBundleID ?? existing.sourceBundleID
            updated.sourceAppName = sourceAppName ?? existing.sourceAppName
            updated.formats = snapshot.formatSummary
            if let titleOverride { updated.title = titleOverride }
            if let sourcePath { updated.sourcePath = sourcePath }
            try? db.write { db in try updated.update(db) }
            try? blobs.save(snapshot: snapshot, for: existing.uuid)
            bump()
            return updated
        }

        var clip = Clip(id: nil, uuid: UUID().uuidString, createdAt: now, updatedAt: now, kind: c.kind, title: titleOverride ?? c.title, text: c.text, contentHash: c.contentHash, byteCount: c.byteCount, sourceBundleID: sourceBundleID, sourceAppName: sourceAppName, pinned: false, collectionID: nil, position: now.timeIntervalSince1970, language: c.language, imageWidth: c.imageWidth, imageHeight: c.imageHeight, linkTitle: nil, linkHost: c.linkHost, lineCount: c.lineCount, charCount: c.charCount, hasRich: c.hasRich, colorHex: c.colorHex, formats: snapshot.formatSummary, sourcePath: sourcePath)
        do {
            try blobs.save(snapshot: snapshot, for: clip.uuid)
            if let data = c.imageData { blobs.saveThumbnail(from: data, for: clip.uuid) }
            try db.write { db in try clip.insert(db) }
        } catch {
            NSLog("ingest failed: \(error)")
            blobs.delete(uuid: clip.uuid)
            return nil
        }
        applyRetention()
        bump()
        if clip.kind == .link { fetchLinkMetadata(for: clip) }
        return clip
    }

    /// Makes a new clip from text the user edited. It lands on top of History.
    @discardableResult
    func createTextClip(_ text: String, sourceBundleID: String? = nil, sourceAppName: String? = nil, rich: NSAttributedString? = nil) -> Clip? {
        var snapshot = PasteboardSnapshot.plainText(text)
        if let rich, let rtf = RichTextConverter.rtfData(rich) {
            snapshot.items[0][PBType.rtf] = rtf
        }
        return ingest(snapshot, sourceBundleID: sourceBundleID ?? Bundle.main.bundleIdentifier, sourceAppName: sourceAppName ?? "ClipKeeper")
    }

    /// Makes a new image clip from PNG data. It lands on top of History.
    @discardableResult
    func createImageClip(png: Data) -> Clip? {
        ingest(.image(png: png), sourceBundleID: Bundle.main.bundleIdentifier, sourceAppName: "ClipKeeper")
    }

    @discardableResult
    func createColorClip(_ color: NSColor) -> Clip? {
        guard let parsed = ParsedColor(nsColor: color) else { return nil }
        return ingest(.color(parsed.nsColor, text: parsed.hex), sourceBundleID: Bundle.main.bundleIdentifier, sourceAppName: "ClipKeeper")
    }

    private func fetchLinkMetadata(for clip: Clip) {
        guard prefs.fetchLinkTitles, let url = URL(string: clip.text) else { return }
        let uuid = clip.uuid
        let host = clip.linkHost
        linkTasks[uuid]?.cancel()
        linkTasks[uuid] = Task { @MainActor [weak self] in
            let result = await LinkMetadata.fetch(url)
            guard let self, !Task.isCancelled else { return }
            self.applyLinkMetadata(result, uuid: uuid, host: host)
        }
    }

    private func applyLinkMetadata(_ result: LinkMetadata.Result, uuid: String, host: String?) {
        if let data = result.faviconData, let host { blobs.saveFavicon(data, forHost: host) }
        if let title = result.title {
            try? db.write { db in
                try db.execute(sql: "UPDATE clip SET linkTitle = ?, title = ? WHERE uuid = ?", arguments: [title, title, uuid])
            }
        }
        linkTasks[uuid] = nil
        bump()
    }

    // MARK: Mutations

    func delete(_ clips: [Clip]) {
        guard !clips.isEmpty else { return }
        try? db.write { db in
            for c in clips { try db.execute(sql: "DELETE FROM clip WHERE uuid = ?", arguments: [c.uuid]) }
        }
        for c in clips { blobs.delete(uuid: c.uuid) }
        bump()
    }

    func togglePin(_ clip: Clip) {
        try? db.write { db in
            try db.execute(sql: "UPDATE clip SET pinned = NOT pinned, updatedAt = ? WHERE uuid = ?", arguments: [Date(), clip.uuid])
        }
        bump()
    }

    /// Moves clips into a set. In a collection they go to the top.
    func move(_ clips: [Clip], to set: ClipSet) {
        let now = Date()
        try? db.write { db in
            for (i, c) in clips.enumerated() {
                try db.execute(sql: "UPDATE clip SET collectionID = ?, position = ?, updatedAt = ? WHERE uuid = ?", arguments: [set.collectionID, now.timeIntervalSince1970 + Double(clips.count - i) * 0.001, now, c.uuid])
            }
        }
        bump()
    }

    /// Copies clips into a set, as new records that share content.
    func copy(_ clips: [Clip], to set: ClipSet) {
        let now = Date()
        try? db.write { db in
            for (i, c) in clips.enumerated() {
                var dup = c
                dup.id = nil
                dup.uuid = UUID().uuidString
                dup.collectionID = set.collectionID
                dup.position = now.timeIntervalSince1970 + Double(clips.count - i) * 0.001
                dup.createdAt = set.collectionID == nil ? now : c.createdAt
                dup.updatedAt = now
                dup.pinned = false
                try self.blobs.duplicate(uuid: c.uuid, to: dup.uuid)
                try dup.insert(db)
            }
        }
        bump()
    }

    @discardableResult
    func duplicate(_ clip: Clip) -> Clip? {
        let now = Date()
        var dup = clip
        dup.id = nil
        dup.uuid = UUID().uuidString
        dup.createdAt = now
        dup.updatedAt = now
        dup.position = now.timeIntervalSince1970
        dup.pinned = false
        do {
            try blobs.duplicate(uuid: clip.uuid, to: dup.uuid)
            try db.write { db in try dup.insert(db) }
            bump()
            return dup
        } catch {
            return nil
        }
    }

    func moveToTop(_ clip: Clip) {
        let now = Date()
        try? db.write { db in
            if clip.collectionID == nil {
                try db.execute(sql: "UPDATE clip SET createdAt = ?, position = ?, updatedAt = ? WHERE uuid = ?", arguments: [now, now.timeIntervalSince1970, now, clip.uuid])
            } else {
                try db.execute(sql: "UPDATE clip SET position = ?, updatedAt = ? WHERE uuid = ?", arguments: [now.timeIntervalSince1970, now, clip.uuid])
            }
        }
        bump()
    }

    func clearHistory() {
        let victims = (try? db.read { db in try Clip.filter(Clip.Columns.collectionID == nil).filter(Clip.Columns.pinned == false).fetchAll(db) }) ?? []
        delete(victims)
    }

    // MARK: Retention

    /// Removes unpinned History clips past the count limit or the age limit.
    func applyRetention() {
        var victims: [Clip] = []
        if prefs.historyLimitEnabled {
            let limit = prefs.historyLimit
            let extra = (try? db.read { db in
                try Clip.fetchAll(db, sql: "SELECT * FROM clip WHERE collectionID IS NULL AND pinned = 0 ORDER BY position DESC, id DESC LIMIT -1 OFFSET ?", arguments: [limit])
            }) ?? []
            victims.append(contentsOf: extra)
        }
        if prefs.ageLimitEnabled {
            let cutoff = Date().addingTimeInterval(-Double(prefs.ageLimitDays) * 86_400)
            let old = (try? db.read { db in
                try Clip.filter(Clip.Columns.collectionID == nil).filter(Clip.Columns.pinned == false).filter(Clip.Columns.createdAt < cutoff).fetchAll(db)
            }) ?? []
            victims.append(contentsOf: old)
        }
        var seen = Set<String>()
        let unique = victims.filter { seen.insert($0.uuid).inserted }
        if !unique.isEmpty {
            try? db.write { db in
                for c in unique { try db.execute(sql: "DELETE FROM clip WHERE uuid = ?", arguments: [c.uuid]) }
            }
            for c in unique { blobs.delete(uuid: c.uuid) }
        }
    }

    /// Bytes used on disk by the database and blobs.
    func storageBytes() -> Int64 {
        var total = blobs.totalSize()
        if let path = db.path as String?, let attrs = try? FileManager.default.attributesOfItem(atPath: path), let size = attrs[.size] as? Int64 {
            total += size
        }
        return total
    }
}
