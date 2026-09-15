import AppKit
import Highlightr
import MarkdownUI
import SwiftUI

/// Syntax highlighting through highlight.js (Highlightr), with a cache.
@MainActor
final class CodeHighlighter {
    static let shared = CodeHighlighter()

    private var highlightr: Highlightr?
    private let cache = NSCache<NSString, NSAttributedString>()
    private var isDark = false
    private var warming = false

    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    private init() {
        cache.countLimit = 400
    }

    /// Loads highlight.js on a background thread. The load takes about a
    /// second, so it must not run on the main thread during a capture.
    func warmUp() {
        guard highlightr == nil, !warming else { return }
        warming = true
        DispatchQueue.global(qos: .userInitiated).async {
            let h = CodeHighlighter.makeHighlightr()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if self.highlightr == nil { self.highlightr = h; self.applyTheme() }
                    self.warming = false
                }
            }
        }
    }

    nonisolated private static func makeHighlightr() -> Highlightr? {
        Highlightr()
    }

    private func ensureLoaded() {
        if highlightr == nil {
            highlightr = Highlightr()
            applyTheme()
        }
    }

    private func applyTheme() {
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        isDark = dark
        highlightr?.setTheme(to: dark ? "atom-one-dark" : "xcode")
        highlightr?.theme.setCodeFont(CodeHighlighter.font)
    }

    /// Re-applies the theme when the system appearance changes.
    func appearanceChanged() {
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if dark != isDark {
            applyTheme()
            cache.removeAllObjects()
        }
    }

    var backgroundColor: NSColor {
        highlightr?.theme.themeBackgroundColor ?? (isDark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.97, alpha: 1))
    }

    /// Highlights code. `language` is a ClipKeeper language id or nil for auto.
    func highlight(_ code: String, language: String?, maxLines: Int? = nil) -> NSAttributedString {
        ensureLoaded()
        var source = code
        if let maxLines {
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > maxLines { source = lines.prefix(maxLines).joined(separator: "\n") + "\n…" }
        }
        let hljsName = CodeLanguage.named(language)?.hljs ?? language
        let key = "\(hljsName ?? "auto")|\(isDark)|\(source.hashValue)|\(source.count)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        var result: NSAttributedString?
        if source.count <= 40_000 {
            result = highlightr?.highlight(source, as: hljsName, fastRender: true)
            if result == nil, hljsName != nil { result = highlightr?.highlight(source, as: nil, fastRender: true) }
        }
        let final = result ?? NSAttributedString(string: source, attributes: [.font: CodeHighlighter.font, .foregroundColor: NSColor.labelColor])
        cache.setObject(final, forKey: key)
        return final
    }

    func highlightedText(_ code: String, language: String?, maxLines: Int? = nil) -> Text {
        Text(AttributedString(highlight(code, language: language, maxLines: maxLines)))
    }
}

/// MarkdownUI hook so fenced code blocks inside Markdown get highlighted.
struct HighlightrSyntaxHighlighter: CodeSyntaxHighlighter {
    func highlightCode(_ code: String, language: String?) -> Text {
        MainActor.assumeIsolated {
            CodeHighlighter.shared.highlightedText(code.trimmingCharacters(in: .newlines), language: language)
        }
    }
}

extension MarkdownUI.Theme {
    /// A compact theme for the shelf.
    static let clipKeeper: MarkdownUI.Theme = MarkdownUI.Theme.gitHub
        .text { FontSize(13) }
        .code { FontFamilyVariant(.monospaced); FontSize(.em(0.9)) }
        .heading1 { cfg in cfg.label.markdownMargin(top: 8, bottom: 6).markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.5)) } }
        .heading2 { cfg in cfg.label.markdownMargin(top: 8, bottom: 4).markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.3)) } }
        .heading3 { cfg in cfg.label.markdownMargin(top: 6, bottom: 4).markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.15)) } }
        .paragraph { cfg in cfg.label.relativeLineSpacing(.em(0.15)).markdownMargin(top: 0, bottom: 8) }
        .codeBlock { cfg in
            ScrollView(.horizontal, showsIndicators: false) {
                cfg.label
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle { FontFamilyVariant(.monospaced); FontSize(.em(0.88)) }
                    .padding(10)
            }
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .markdownMargin(top: 0, bottom: 10)
        }
}
