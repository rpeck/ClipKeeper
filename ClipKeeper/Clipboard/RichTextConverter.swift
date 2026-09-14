import AppKit
import Foundation

/// Reads rich text from a snapshot and converts it to Markdown, HTML, or RTF.
enum RichTextConverter {
    /// The best attributed string a snapshot offers: RTFD, then RTF, then HTML.
    static func attributedString(from snapshot: PasteboardSnapshot) -> NSAttributedString? {
        if let d = snapshot.data(for: PBType.rtfd), let a = NSAttributedString(rtfd: d, documentAttributes: nil) { return a }
        if let d = snapshot.data(for: PBType.rtf), let a = NSAttributedString(rtf: d, documentAttributes: nil) { return a }
        if let d = snapshot.data(for: PBType.html),
           let a = NSAttributedString(html: d, options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) { return a }
        return nil
    }

    static func rtfData(_ attributed: NSAttributedString) -> Data? {
        try? attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    static func rtfdData(_ attributed: NSAttributedString) -> Data? {
        attributed.rtfd(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    }

    static func htmlData(_ attributed: NSAttributedString) -> Data? {
        try? attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue])
    }

    // MARK: Markdown

    /// A list marker TextKit put into the text: optional tab, the marker, then a tab or spaces.
    private static let literalMarker = try! NSRegularExpression(pattern: #"^[\t ]*(?:[•◦▪‣\-\*·]|\d+[.)]?|[a-zA-Z][.)])[\t ]+"#)

    /// Converts an attributed string to Markdown. Handles headings (by font
    /// size), bold, italic, code (monospaced font), links, strikethrough,
    /// bullet and numbered lists, and paragraph breaks.
    static func markdown(from attributed: NSAttributedString) -> String {
        let text = attributed.string
        guard !text.isEmpty else { return "" }
        let bodySize = dominantFontSize(attributed)

        var output: [String] = []
        let nsText = text as NSString
        var paragraphIndex = 0
        var location = 0
        var previousWasList = false

        while location < nsText.length {
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: location, length: 0))
            var sub = attributed.attributedSubstring(from: paragraphRange)
            // TextKit writes list markers into the text as "\t•\t" or "\t1.\t". Remove them.
            var literalMarkerKind: String? = nil
            if let m = literalMarker.firstMatch(in: sub.string, range: NSRange(location: 0, length: sub.length)), m.range.length < sub.length {
                let marker = (sub.string as NSString).substring(with: m.range).trimmingCharacters(in: .whitespaces)
                literalMarkerKind = marker.first?.isNumber == true || marker.first?.isLetter == true ? "ordered" : "bullet"
                sub = sub.attributedSubstring(from: NSRange(location: m.range.length, length: sub.length - m.range.length))
            }
            var line = sub.string
            while line.hasSuffix("\n") || line.hasSuffix("\r") || line.hasSuffix("\u{2029}") { line.removeLast() }

            let attrsAtStart = sub.length > 0 ? sub.attributes(at: 0, effectiveRange: nil) : [:]
            let paragraphStyle = attrsAtStart[.paragraphStyle] as? NSParagraphStyle
            let lists = paragraphStyle?.textLists ?? []

            var prefix = ""
            var isList = false
            if let list = lists.last {
                isList = true
                let depth = max(0, lists.count - 1)
                let indent = String(repeating: "  ", count: depth)
                let format = list.markerFormat.rawValue
                if format.contains("decimal") || format.contains("lower") || format.contains("upper") || literalMarkerKind == "ordered" {
                    paragraphIndex += 1
                    prefix = indent + "\(paragraphIndex). "
                } else {
                    prefix = indent + "- "
                }
            } else if let kind = literalMarkerKind {
                isList = true
                if kind == "ordered" {
                    paragraphIndex += 1
                    prefix = "\(paragraphIndex). "
                } else {
                    prefix = "- "
                }
            } else {
                paragraphIndex = 0
            }

            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty {
                if !(output.last?.isEmpty ?? true) { output.append("") }
                location = NSMaxRange(paragraphRange)
                previousWasList = false
                continue
            }

            // Heading by font size, when the whole paragraph is one size.
            var headingLevel = 0
            if !isList, let size = uniformFontSize(sub), size > bodySize * 1.12 {
                let ratio = size / bodySize
                headingLevel = ratio >= 1.9 ? 1 : ratio >= 1.45 ? 2 : ratio >= 1.25 ? 3 : 4
            }

            // Whole paragraph in monospaced font → code block.
            if !isList, headingLevel == 0, isWhollyMonospaced(sub) {
                if output.last?.hasPrefix("```") == true, output.count >= 2, output[output.count - 1] == "```" {
                    output.removeLast()
                    output.append(line)
                    output.append("```")
                } else {
                    if !(output.last?.isEmpty ?? true) { output.append("") }
                    output.append("```")
                    output.append(line)
                    output.append("```")
                }
                location = NSMaxRange(paragraphRange)
                previousWasList = false
                continue
            }

            let inline = inlineMarkdown(sub, stripLeading: line.count < sub.string.count ? sub.string.count - line.count : 0)
            var rendered = inline.trimmingCharacters(in: .whitespaces)
            if headingLevel > 0 {
                rendered = rendered.replacingOccurrences(of: "**", with: "")
                rendered = String(repeating: "#", count: headingLevel) + " " + rendered
                if !(output.last?.isEmpty ?? true) { output.append("") }
                output.append(rendered)
                output.append("")
            } else if isList {
                if !previousWasList, !(output.last?.isEmpty ?? true) { output.append("") }
                output.append(prefix + rendered)
            } else {
                if previousWasList { output.append("") }
                output.append(rendered)
                output.append("")
            }
            previousWasList = isList
            location = NSMaxRange(paragraphRange)
        }

        var result = output.joined(separator: "\n")
        while result.contains("\n\n\n") { result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return result.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func dominantFontSize(_ a: NSAttributedString) -> CGFloat {
        var counts: [CGFloat: Int] = [:]
        a.enumerateAttribute(.font, in: NSRange(location: 0, length: a.length)) { value, range, _ in
            let size = (value as? NSFont)?.pointSize ?? 12
            counts[size, default: 0] += range.length
        }
        return counts.max { $0.value < $1.value }?.key ?? 12
    }

    private static func uniformFontSize(_ a: NSAttributedString) -> CGFloat? {
        var sizes = Set<CGFloat>()
        a.enumerateAttribute(.font, in: NSRange(location: 0, length: a.length)) { value, range, _ in
            let str = (a.string as NSString).substring(with: range)
            if str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
            sizes.insert((value as? NSFont)?.pointSize ?? 12)
        }
        return sizes.count == 1 ? sizes.first : nil
    }

    private static func isWhollyMonospaced(_ a: NSAttributedString) -> Bool {
        guard a.length > 0 else { return false }
        var allMono = true
        var sawText = false
        a.enumerateAttribute(.font, in: NSRange(location: 0, length: a.length)) { value, range, _ in
            let str = (a.string as NSString).substring(with: range)
            if str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
            sawText = true
            if let f = value as? NSFont, f.isFixedPitch || f.fontDescriptor.symbolicTraits.contains(.monoSpace) { return }
            allMono = false
        }
        return sawText && allMono
    }

    /// Renders runs with inline marks: bold, italic, code, strikethrough, links.
    private static func inlineMarkdown(_ a: NSAttributedString, stripLeading: Int) -> String {
        var result = ""
        let full = NSRange(location: 0, length: a.length)
        a.enumerateAttributes(in: full) { attrs, range, _ in
            var run = (a.string as NSString).substring(with: range)
            run = run.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\u{2029}", with: "")
            if attrs[.attachment] != nil { return }
            guard !run.isEmpty else { return }
            let leading = run.prefix { $0 == " " || $0 == "\t" }
            let trailing = run.reversed().prefix { $0 == " " || $0 == "\t" }
            let core = run.trimmingCharacters(in: .whitespaces)
            if core.isEmpty { result += run; return }

            var wrapped = core
            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let mono = font.map { $0.isFixedPitch || traits.contains(.monoSpace) } ?? false
            if mono {
                wrapped = "`\(wrapped)`"
            } else {
                if traits.contains(.bold) { wrapped = "**\(wrapped)**" }
                if traits.contains(.italic) { wrapped = "*\(wrapped)*" }
            }
            if let s = attrs[.strikethroughStyle] as? Int, s != 0 { wrapped = "~~\(wrapped)~~" }
            if let link = attrs[.link] {
                let urlString = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
                if !urlString.isEmpty { wrapped = "[\(wrapped)](\(urlString))" }
            }
            result += String(leading) + wrapped + String(trailing.reversed())
        }
        // Merge adjacent identical marks like "**a****b**".
        result = result.replacingOccurrences(of: "****", with: "")
        result = result.replacingOccurrences(of: "``", with: "")
        return result
    }
}
