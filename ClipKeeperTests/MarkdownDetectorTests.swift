import Testing
@testable import ClipKeeper

@Suite struct MarkdownDetectorTests {
    @Test func headingsAndLists() {
        let md = """
        # Plan

        - First item
        - Second item

        ## Notes
        Some **bold** text and a [link](https://example.com).
        """
        let r = MarkdownDetector.detect(md)
        #expect(r.isMarkdown)
        #expect(r.hasStructure)
    }

    @Test func fencedCode() {
        let md = "Run this:\n\n```sh\nbrew install xcodegen\n```\n"
        #expect(MarkdownDetector.detect(md).isMarkdown)
    }

    @Test func table() {
        let md = "| a | b |\n|---|---|\n| 1 | 2 |\n"
        let r = MarkdownDetector.detect(md)
        #expect(r.isMarkdown)
        #expect(r.hasStructure)
    }

    @Test func plainProse() {
        let text = "This is a normal sentence. It has no markdown in it at all. Just words."
        #expect(!MarkdownDetector.detect(text).isMarkdown)
    }

    @Test func hashtagIsNotHeading() {
        #expect(!MarkdownDetector.detect("#winning #blessed").isMarkdown)
    }

    @Test func twoBulletsAreWeak() {
        #expect(!MarkdownDetector.detect("- milk\n- eggs").isMarkdown)
    }

    @Test func longBulletList() {
        #expect(MarkdownDetector.detect("- milk\n- eggs\n- bread\n- butter\n- jam").isMarkdown)
    }
}
