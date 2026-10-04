import AppKit
import Foundation
import Testing
@testable import ClipKeeper

@Suite @MainActor struct FileImporterTests {
    let dir: URL
    let store: ClipStore
    let prefs: Preferences

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("FileImporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "FileImporterTests-\(UUID().uuidString)"))
        prefs = Preferences(defaults: defaults)
        prefs.fetchLinkTitles = false
        store = ClipStore(database: try Database.inMemory(), blobs: .temporary(), prefs: prefs)
    }

    private func write(_ name: String, _ text: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func writePNG(_ name: String, width: Int = 12, height: Int = 8) throws -> URL {
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(NSColor.green.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(ctx.makeImage())
        let data = try #require(ImageConversion.data(from: image, format: .png))
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    @Test func markdownFileBecomesMarkdownClip() throws {
        let url = try write("notes.md", "# Plan\n\n- one\n- two\n- three\n\nSee the [doc](https://example.com).\n")
        let item = try FileImporter.read(url, imageLimit: nil)
        let clip = try #require(store.ingest(item.snapshot, sourceBundleID: "com.apple.finder", sourceAppName: "Finder", title: url.lastPathComponent, sourcePath: url.path))
        #expect(clip.kind == .markdown)
        #expect(clip.title == "notes.md")
        #expect(clip.sourcePath == url.path)
        #expect(clip.sourceAppName == "Finder")
    }

    @Test func pythonFileBecomesCodeClip() throws {
        let url = try write("tool.py", "import sys\n\ndef main(argv):\n    print(argv)\n\nif __name__ == \"__main__\":\n    main(sys.argv)\n")
        let item = try FileImporter.read(url, imageLimit: nil)
        let clip = try #require(store.ingest(item.snapshot, sourceBundleID: nil, sourceAppName: nil, title: url.lastPathComponent))
        #expect(clip.kind == .code)
        #expect(clip.language == "python")
    }

    @Test func pngFileBecomesImageClip() throws {
        let url = try writePNG("pic.png")
        let item = try FileImporter.read(url, imageLimit: nil)
        #expect(item.snapshot.has(PBType.png))
        let clip = try #require(store.ingest(item.snapshot, sourceBundleID: nil, sourceAppName: nil, title: url.lastPathComponent))
        #expect(clip.kind == .image)
        #expect(clip.imageWidth == 12)
        #expect(clip.formats == "PNG")
    }

    @Test func rtfFileBecomesRichTextClip() throws {
        let a = NSMutableAttributedString(string: "Hello bold world", attributes: [.font: NSFont.systemFont(ofSize: 13)])
        a.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: NSRange(location: 6, length: 4))
        let rtf = try #require(RichTextConverter.rtfData(a))
        let url = dir.appendingPathComponent("doc.rtf")
        try rtf.write(to: url)
        let item = try FileImporter.read(url, imageLimit: nil)
        #expect(item.snapshot.has(PBType.rtf))
        #expect(item.snapshot.string == "Hello bold world")
        let clip = try #require(store.ingest(item.snapshot, sourceBundleID: nil, sourceAppName: nil))
        #expect(clip.kind == .richText)
    }

    @Test func unknownExtensionWithTextContentIsText() throws {
        let url = try write("server.log", "2026-10-04 12:00:01 started\n2026-10-04 12:00:02 listening on 8080\n")
        let item = try FileImporter.read(url, imageLimit: nil)
        #expect(item.snapshot.string?.contains("listening") == true)
    }

    @Test func binaryFileIsRejected() throws {
        let url = dir.appendingPathComponent("blob.bin")
        try Data([0, 1, 2, 3, 0, 255, 254, 0]).write(to: url)
        #expect(throws: FileImporter.Problem.self) { try FileImporter.read(url, imageLimit: nil) }
    }

    @Test func imageAboveLimitIsRejected() throws {
        let url = try writePNG("big.png", width: 64, height: 64)
        #expect(throws: FileImporter.Problem.self) { try FileImporter.read(url, imageLimit: 10) }
    }

    @Test func folderExpandsOneLevelInNameOrder() throws {
        let folder = dir.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "b".write(to: folder.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "a".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try ".hidden".write(to: folder.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        let nested = folder.appendingPathComponent("deeper", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "c".write(to: nested.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        let expanded = FileImporter.expand([folder])
        #expect(expanded.map(\.lastPathComponent) == ["a.txt", "b.txt"])
    }

    @Test func coordinatorKeepsDropOrderFirstFileOnTop() throws {
        let one = try write("one.txt", "first file")
        let two = try write("two.txt", "second file")
        let three = try write("three.txt", "third file")
        let coordinator = ImportCoordinator(store: store, prefs: prefs)
        let outcome = coordinator.importFiles([one, two, three])
        #expect(outcome.imported.count == 3)
        #expect(outcome.problems.isEmpty)
        #expect(store.clips(in: .history, query: "").map(\.title) == ["one.txt", "two.txt", "three.txt"])
    }

    @Test func coordinatorImportsIntoCollection() throws {
        let c = try #require(store.createCollection(named: "Prompts"))
        let url = try write("prompt.md", "# Prompt\n\nWrite a haiku about clipboards.\n")
        let coordinator = ImportCoordinator(store: store, prefs: prefs)
        let outcome = coordinator.importFiles([url], into: .collection(c))
        #expect(outcome.imported.count == 1)
        #expect(store.clips(in: .history, query: "").isEmpty)
        #expect(store.clips(in: .collection(c), query: "").first?.title == "prompt.md")
    }

    @Test func coordinatorReportsSkippedFiles() throws {
        let good = try write("ok.txt", "fine")
        let bad = dir.appendingPathComponent("bad.bin")
        try Data([0, 0, 0, 0, 1]).write(to: bad)
        let coordinator = ImportCoordinator(store: store, prefs: prefs)
        let outcome = coordinator.importFiles([good, bad])
        #expect(outcome.imported.count == 1)
        #expect(outcome.problems.count == 1)
        #expect(outcome.summary == "Imported 1 file · 1 skipped")
    }
}
