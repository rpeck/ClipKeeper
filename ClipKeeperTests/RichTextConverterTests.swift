import AppKit
import Testing
@testable import ClipKeeper

@Suite struct RichTextConverterTests {
    private func attributed(_ html: String) throws -> NSAttributedString {
        try #require(NSAttributedString(html: Data(html.utf8), options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil))
    }

    @Test func boldItalicLink() throws {
        let a = try attributed("<p>Hello <b>bold</b> and <i>italic</i> and <a href=\"https://example.com\">link</a>.</p>")
        let md = RichTextConverter.markdown(from: a)
        #expect(md.contains("**bold**"), "\(md)")
        #expect(md.contains("*italic*"), "\(md)")
        #expect(md.contains("[link](https://example.com"), "\(md)")
    }

    @Test func headings() throws {
        let a = try attributed("<h1>Title</h1><p>Body text here.</p><h2>Sub</h2><p>More.</p>")
        let md = RichTextConverter.markdown(from: a)
        #expect(md.hasPrefix("# Title"), "\(md)")
        #expect(md.contains("\n## Sub"), "\(md)")
        #expect(md.contains("Body text here."), "\(md)")
    }

    @Test func bulletList() throws {
        let a = try attributed("<ul><li>Alpha</li><li>Beta</li></ul>")
        let md = RichTextConverter.markdown(from: a)
        #expect(md.contains("- Alpha"), "\(md)")
        #expect(md.contains("- Beta"), "\(md)")
    }

    @Test func numberedList() throws {
        let a = try attributed("<ol><li>One</li><li>Two</li></ol>")
        let md = RichTextConverter.markdown(from: a)
        #expect(md.contains("1. One"), "\(md)")
        #expect(md.contains("2. Two"), "\(md)")
    }

    @Test func inlineCode() {
        let a = NSMutableAttributedString(string: "Run brew install now", attributes: [.font: NSFont.systemFont(ofSize: 13)])
        a.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: NSRange(location: 4, length: 12))
        let md = RichTextConverter.markdown(from: a)
        #expect(md.contains("`brew install`"), "\(md)")
    }

    @Test func plainParagraphsSeparated() throws {
        let a = try attributed("<p>First.</p><p>Second.</p>")
        let md = RichTextConverter.markdown(from: a)
        #expect(md == "First.\n\nSecond.\n", "\(md)")
    }
}
