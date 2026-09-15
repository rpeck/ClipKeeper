import AppKit
import Foundation
import Testing
@testable import ClipKeeper

/// The monitor against a private pasteboard, driven tick by tick.
@Suite @MainActor struct PasteboardMonitorTests {
    let store: ClipStore
    let prefs: Preferences
    let pasteboard: NSPasteboard
    let monitor: PasteboardMonitor

    init() throws {
        let defaults = try #require(UserDefaults(suiteName: "MonitorTests-\(UUID().uuidString)"))
        prefs = Preferences(defaults: defaults)
        prefs.fetchLinkTitles = false
        store = ClipStore(database: try Database.inMemory(), blobs: .temporary(), prefs: prefs)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipKeeperTests-\(UUID().uuidString)"))
        monitor = PasteboardMonitor(store: store, prefs: prefs, pasteboard: pasteboard)
    }

    private func png() throws -> Data {
        let ctx = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(ctx.makeImage())
        return try #require(ImageConversion.data(from: image, format: .png))
    }

    @Test func completeCopyIsStoredAfterTwoReads() {
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        monitor.check()
        #expect(store.clips(in: .history, query: "").isEmpty)   // first read only observes
        monitor.check()
        let clips = store.clips(in: .history, query: "")
        #expect(clips.count == 1)
        #expect(clips.first?.text == "hello")
    }

    @Test func dataThatLandsAfterTheDeclarationIsNotMissed() throws {
        // Chromium style: declare types, set the small type, set the image later.
        let image = try png()
        pasteboard.declareTypes([.html, .png], owner: nil)
        pasteboard.setData(Data("<img src=\"x\">".utf8), forType: .html)
        monitor.check()
        monitor.check()
        monitor.check()
        #expect(store.clips(in: .history, query: "").isEmpty)   // incomplete: nothing stored, still watching
        pasteboard.setData(image, forType: .png)
        monitor.check()   // sees the change, not yet stable
        #expect(store.clips(in: .history, query: "").isEmpty)
        monitor.check()   // stable and complete
        let clips = store.clips(in: .history, query: "")
        #expect(clips.count == 1)
        #expect(clips.first?.kind == .image)
        #expect(clips.first?.formats == "PNG, HTML")
    }

    @Test func emptyPasteboardAfterClearIsNotConsumed() {
        pasteboard.clearContents()   // the count moves, nothing is written yet
        monitor.check()
        monitor.check()
        #expect(store.clips(in: .history, query: "").isEmpty)
        pasteboard.setString("late", forType: .string)   // same change count
        monitor.check()
        monitor.check()
        #expect(store.clips(in: .history, query: "").first?.text == "late")
    }

    @Test func incompleteChangeIsDroppedAfterTimeout() {
        monitor.settleTimeout = 0
        pasteboard.declareTypes([.html], owner: nil)
        pasteboard.setData(Data("<img src=\"x\">".utf8), forType: .html)
        monitor.check()
        monitor.check()   // timed out: dropped
        #expect(store.clips(in: .history, query: "").isEmpty)
        pasteboard.clearContents()
        pasteboard.setString("next", forType: .string)
        monitor.check()
        monitor.check()
        #expect(store.clips(in: .history, query: "").first?.text == "next")
    }

    @Test func pausedCopiesAreSkipped() {
        prefs.isPaused = true
        pasteboard.clearContents()
        pasteboard.setString("secret", forType: .string)
        monitor.check()
        monitor.check()
        #expect(store.clips(in: .history, query: "").isEmpty)
        prefs.isPaused = false
        pasteboard.clearContents()
        pasteboard.setString("public", forType: .string)
        monitor.check()
        monitor.check()
        #expect(store.clips(in: .history, query: "").count == 1)
    }

    @Test func concealedCopiesAreSkipped() {
        pasteboard.clearContents()
        pasteboard.setString("hunter2", forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType(PBType.concealed))
        monitor.check()
        monitor.check()
        #expect(store.clips(in: .history, query: "").isEmpty)
    }
}
