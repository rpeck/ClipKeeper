import Foundation
import Testing
@testable import ClipKeeper

@Suite @MainActor struct ClipStoreTests {
    let store: ClipStore
    let prefs: Preferences

    init() throws {
        let defaults = try #require(UserDefaults(suiteName: "ClipKeeperTests-\(UUID().uuidString)"))
        prefs = Preferences(defaults: defaults)
        prefs.fetchLinkTitles = false
        store = ClipStore(database: try Database.inMemory(), blobs: .temporary(), prefs: prefs)
    }

    @Test func ingestAndRead() {
        let clip = store.ingest(.plainText("hello world"), sourceBundleID: "com.apple.Safari", sourceAppName: "Safari")
        #expect(clip != nil)
        let clips = store.clips(in: .history, query: "")
        #expect(clips.count == 1)
        #expect(clips[0].text == "hello world")
        #expect(clips[0].sourceAppName == "Safari")
        #expect(store.snapshot(for: clips[0]) != nil)
    }

    @Test func duplicateMovesToTop() {
        store.ingest(.plainText("one"), sourceBundleID: nil, sourceAppName: nil)
        store.ingest(.plainText("two"), sourceBundleID: nil, sourceAppName: nil)
        store.ingest(.plainText("one"), sourceBundleID: nil, sourceAppName: nil)
        let clips = store.clips(in: .history, query: "")
        #expect(clips.count == 2)
        #expect(clips.map(\.text) == ["one", "two"])
    }

    @Test func search() {
        store.ingest(.plainText("alpha beta gamma"), sourceBundleID: nil, sourceAppName: nil)
        store.ingest(.plainText("delta epsilon"), sourceBundleID: nil, sourceAppName: nil)
        store.ingest(.plainText("func gammaRay() {}"), sourceBundleID: nil, sourceAppName: nil)
        let hits = store.clips(in: .history, query: "gam")
        #expect(hits.count == 2)
        #expect(hits.allSatisfy { $0.text.lowercased().contains("gam") })
        #expect(store.clips(in: .history, query: "zzz").isEmpty)
    }

    @Test func pinAndOrder() {
        store.ingest(.plainText("older"), sourceBundleID: nil, sourceAppName: nil)
        store.ingest(.plainText("newer"), sourceBundleID: nil, sourceAppName: nil)
        let older = store.clips(in: .history, query: "")[1]
        store.togglePin(older)
        let clips = store.clips(in: .history, query: "")
        #expect(clips[0].text == "older")
        #expect(clips[0].pinned)
    }

    @Test func collectionsMoveAndDelete() throws {
        let c = try #require(store.createCollection(named: "Work"))
        store.ingest(.plainText("task"), sourceBundleID: nil, sourceAppName: nil)
        let clip = store.clips(in: .history, query: "")[0]
        store.move([clip], to: .collection(c))
        #expect(store.clips(in: .history, query: "").isEmpty)
        #expect(store.clips(in: .collection(c), query: "").count == 1)
        // A new copy of the same text goes to History; the collection copy stays.
        store.ingest(.plainText("task"), sourceBundleID: nil, sourceAppName: nil)
        #expect(store.clips(in: .history, query: "").count == 1)
        #expect(store.clips(in: .collection(c), query: "").count == 1)
        store.deleteCollection(c)
        #expect(store.collections.isEmpty)
        #expect(store.clips(in: .history, query: "").count == 2)
    }

    @Test func duplicateClip() throws {
        store.ingest(.plainText("dup me"), sourceBundleID: nil, sourceAppName: nil)
        let clip = store.clips(in: .history, query: "")[0]
        let dup = try #require(store.duplicate(clip))
        #expect(store.clips(in: .history, query: "").count == 2)
        #expect(store.snapshot(for: dup) != nil)
    }

    @Test func retentionByCount() {
        prefs.historyLimitEnabled = true
        prefs.historyLimit = 3
        for i in 0..<6 { store.ingest(.plainText("clip \(i)"), sourceBundleID: nil, sourceAppName: nil) }
        let clips = store.clips(in: .history, query: "")
        #expect(clips.map(\.text) == ["clip 5", "clip 4", "clip 3"])
    }

    @Test func retentionSparesPinned() {
        prefs.historyLimitEnabled = true
        prefs.historyLimit = 2
        store.ingest(.plainText("keep"), sourceBundleID: nil, sourceAppName: nil)
        store.togglePin(store.clips(in: .history, query: "")[0])
        for i in 0..<4 { store.ingest(.plainText("clip \(i)"), sourceBundleID: nil, sourceAppName: nil) }
        let clips = store.clips(in: .history, query: "")
        #expect(clips.contains { $0.text == "keep" })
        #expect(clips.count == 3)
    }

    @Test func deleteRemovesBlob() {
        store.ingest(.plainText("gone"), sourceBundleID: nil, sourceAppName: nil)
        let clip = store.clips(in: .history, query: "")[0]
        store.delete([clip])
        #expect(store.clips(in: .history, query: "").isEmpty)
        #expect(store.snapshot(for: clip) == nil)
    }

    @Test func editedTextBecomesNewClip() {
        store.ingest(.plainText("original"), sourceBundleID: nil, sourceAppName: nil)
        store.createTextClip("edited")
        let clips = store.clips(in: .history, query: "")
        #expect(clips.map(\.text) == ["edited", "original"])
    }
}
