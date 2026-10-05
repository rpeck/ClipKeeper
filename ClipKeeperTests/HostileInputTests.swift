import Foundation
import Testing
@testable import ClipKeeper

/// Inputs an attacker on the network could send. Every classifier must
/// finish fast on them, because received clips run through the same code.
@Suite struct HostileInputTests {
    private func timed(_ body: () -> Void) -> TimeInterval {
        let start = Date()
        body()
        return Date().timeIntervalSince(start)
    }

    /// Classic ReDoS shapes: long runs that almost match, repeated many times.
    private var hostileTexts: [String] {
        [
            String(repeating: "a", count: 200_000),
            String(repeating: "- ", count: 100_000),
            String(repeating: "**", count: 100_000) + "x",
            String(repeating: "[", count: 50_000) + String(repeating: "]", count: 50_000),
            String(repeating: "(", count: 50_000),
            String(repeating: "#", count: 100_000) + " ",
            String(repeating: "| ", count: 100_000),
            String(repeating: "func f(", count: 20_000),
            String(repeating: "rgb(", count: 50_000),
            String(repeating: "https://", count: 20_000),
            String(repeating: "x = ", count: 50_000),
            String(repeating: "\t", count: 200_000) + "a",
            String(repeating: " \n", count: 100_000),
            String(repeating: "<div ", count: 40_000),
            String(repeating: "SELECT ", count: 30_000),
            String(repeating: "`", count: 100_000),
            String(repeating: "a_", count: 100_000),
            String((0..<200_000).map { _ in "aA1_-.()[]{}:;=<>/\\\"'`#*|\n".randomElement() ?? "a" }),
        ]
    }

    @Test func codeDetectorFinishesFastOnHostileText() {
        for text in hostileTexts {
            let seconds = timed { _ = CodeDetector.detect(text) }
            #expect(seconds < 1.0, "CodeDetector took \(seconds)s on \(text.prefix(20))… (\(text.count) chars)")
        }
    }

    @Test func markdownDetectorFinishesFastOnHostileText() {
        for text in hostileTexts {
            let seconds = timed { _ = MarkdownDetector.detect(text) }
            #expect(seconds < 1.0, "MarkdownDetector took \(seconds)s on \(text.prefix(20))… (\(text.count) chars)")
        }
    }

    @Test func colorParserFinishesFastOnHostileText() {
        for text in hostileTexts {
            let seconds = timed { _ = ColorParser.parse(text) }
            #expect(seconds < 0.1, "ColorParser took \(seconds)s")
        }
    }

    @Test func classifierFinishesFastOnHostileText() {
        for text in hostileTexts {
            let seconds = timed { _ = ContentClassifier.classify(.plainText(text)) }
            #expect(seconds < 2.0, "classify took \(seconds)s on \(text.prefix(20))… (\(text.count) chars)")
        }
    }

    @Test @MainActor func searchQueryWithFTSOperatorsDoesNotThrow() throws {
        let defaults = try #require(UserDefaults(suiteName: "HostileInputTests-\(UUID().uuidString)"))
        let prefs = Preferences(defaults: defaults)
        prefs.fetchLinkTitles = false
        let store = ClipStore(database: try Database.inMemory(), blobs: .temporary(), prefs: prefs)
        store.ingest(.plainText("hello world"), sourceBundleID: nil, sourceAppName: nil)
        for q in ["\"", "AND OR NOT", "hello*\"", "(", "col:x", "a NEAR/5 b", "^hello", "{a b}", "\\", "' OR 1=1 --"] {
            _ = store.clips(in: .history, query: q)
        }
    }
}
