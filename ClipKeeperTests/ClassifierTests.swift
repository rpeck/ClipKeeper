import AppKit
import Testing
@testable import ClipKeeper

@Suite struct ClassifierTests {
    private func snapshot(_ dict: [String: Data]) -> PasteboardSnapshot {
        PasteboardSnapshot(items: [dict])
    }

    @Test func plainText() {
        let c = ContentClassifier.classify(.plainText("B1 Ledge running"))
        #expect(c?.kind == .text)
        #expect(c?.title == "B1 Ledge running")
        #expect(c?.charCount == 16)
    }

    @Test func linkFromText() {
        let c = ContentClassifier.classify(.plainText("https://www.loom.com/share/abc?x=1"))
        #expect(c?.kind == .link)
        #expect(c?.linkHost == "loom.com")
    }

    @Test func linkFromURLType() {
        let snap = snapshot([PBType.url: Data("https://example.com/page".utf8), PBType.string: Data("Example page".utf8)])
        let c = ContentClassifier.classify(snap)
        #expect(c?.kind == .link)
        #expect(c?.text == "https://example.com/page")
    }

    @Test func bareDomainWithPath() {
        #expect(ContentClassifier.classify(.plainText("github.com/groue/GRDB.swift"))?.kind == .link)
        #expect(ContentClassifier.classify(.plainText("example.com"))?.kind == .text)
    }

    @Test func colorFromText() {
        let c = ContentClassifier.classify(.plainText("#4cb39a"))
        #expect(c?.kind == .color)
        #expect(c?.colorHex == "#4CB39A")
    }

    @Test func colorFromObject() {
        let snap = PasteboardSnapshot.color(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), text: "red")
        let c = ContentClassifier.classify(snap)
        #expect(c?.kind == .color)
        #expect(c?.colorHex == "#FF0000")
    }

    @Test func image() throws {
        let ctx = try #require(CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(NSColor.blue.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        let cg = try #require(ctx.makeImage())
        let png = try #require(ImageConversion.data(from: cg, format: .png))
        let c = ContentClassifier.classify(.image(png: png))
        #expect(c?.kind == .image)
        #expect(c?.imageWidth == 20)
        #expect(c?.imageHeight == 10)
    }

    @Test func files() {
        let snap = PasteboardSnapshot(items: [
            [PBType.fileURL: Data("file:///Users/me/a.txt".utf8)],
            [PBType.fileURL: Data("file:///Users/me/b.png".utf8)],
        ])
        let c = ContentClassifier.classify(snap)
        #expect(c?.kind == .files)
        #expect(c?.title == "2 files")
        #expect(c?.text == "/Users/me/a.txt\n/Users/me/b.png")
    }

    @Test func codeText() {
        let src = "def hello(name):\n    print(f\"hi {name}\")\n\nhello(\"x\")\n"
        let c = ContentClassifier.classify(.plainText(src))
        #expect(c?.kind == .code)
        #expect(c?.language == "python")
    }

    @Test func markdownText() {
        let md = "# Title\n\nSome text with **bold**.\n\n- a\n- b\n- c\n"
        #expect(ContentClassifier.classify(.plainText(md))?.kind == .markdown)
    }

    @Test func richText() throws {
        let a = NSMutableAttributedString(string: "Hello bold world", attributes: [.font: NSFont.systemFont(ofSize: 13)])
        a.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: NSRange(location: 6, length: 4))
        let rtf = try #require(RichTextConverter.rtfData(a))
        let snap = snapshot([PBType.string: Data("Hello bold world".utf8), PBType.rtf: rtf])
        let c = ContentClassifier.classify(snap)
        #expect(c?.kind == .richText)
        #expect(c?.hasRich == true)
    }

    @Test func richCopyOfPlainSentenceIsText() throws {
        let a = NSAttributedString(string: "Just a sentence from a web page.", attributes: [.font: NSFont.systemFont(ofSize: 13)])
        let rtf = try #require(RichTextConverter.rtfData(a))
        let snap = snapshot([PBType.string: Data("Just a sentence from a web page.".utf8), PBType.rtf: rtf])
        #expect(ContentClassifier.classify(snap)?.kind == .text)
    }

    @Test func emptyIsNil() {
        #expect(ContentClassifier.classify(.plainText("   \n")) == nil)
    }

    @Test func snapshotRoundTrip() throws {
        let snap = snapshot([PBType.string: Data("abc".utf8), "com.example.custom": Data([1, 2, 3])])
        let data = try snap.serialized()
        let back = PasteboardSnapshot(serialized: data)
        #expect(back == snap)
    }
}
