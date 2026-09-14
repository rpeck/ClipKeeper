import AppKit
import CryptoKit
import Foundation

/// The result of classification: everything the store needs to make a Clip.
struct Classification {
    var kind: ClipKind
    var title: String
    var text: String
    var contentHash: String
    var byteCount: Int
    var language: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var linkHost: String?
    var lineCount: Int
    var charCount: Int
    var hasRich: Bool
    var colorHex: String?
    /// Raw image data for the thumbnail, when the kind is image.
    var imageData: Data?
    var imageType: String?
}

/// Turns a pasteboard snapshot into a Classification.
enum ContentClassifier {
    static func classify(_ snapshot: PasteboardSnapshot) -> Classification? {
        let byteCount = snapshot.totalByteCount
        let plain = snapshot.string?.replacingOccurrences(of: "\r\n", with: "\n")

        // 1. Files.
        if snapshot.has(PBType.fileURL) || snapshot.has(PBType.legacyFilenames) {
            let paths = filePaths(in: snapshot)
            if !paths.isEmpty {
                let joined = paths.joined(separator: "\n")
                let title = paths.count == 1 ? (paths[0] as NSString).lastPathComponent : "\(paths.count) files"
                return Classification(kind: .files, title: title, text: joined, contentHash: hash("files:" + joined), byteCount: byteCount, lineCount: paths.count, charCount: joined.count, hasRich: false)
            }
        }

        // 2. Images.
        for type in PBType.imageTypes {
            if let data = snapshot.data(for: type) {
                let size = ImageConversion.pixelSize(of: data)
                let title = "Image"
                let hashSource = snapshot.data(for: PBType.png) ?? data
                return Classification(kind: .image, title: title, text: "", contentHash: hash(hashSource), byteCount: byteCount, imageWidth: size.map { Int($0.width) }, imageHeight: size.map { Int($0.height) }, lineCount: 0, charCount: 0, hasRich: false, imageData: data, imageType: type)
            }
        }

        // 3. Colors from a color object.
        if let data = snapshot.data(for: PBType.color),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data),
           let parsed = ParsedColor(nsColor: color) {
            let text = plain ?? parsed.hex
            return Classification(kind: .color, title: parsed.hex, text: text, contentHash: hash("color:" + parsed.hex), byteCount: byteCount, lineCount: 1, charCount: text.count, hasRich: false, colorHex: parsed.hex)
        }

        guard let text = plain ?? htmlOrRTFAsPlain(snapshot) else {
            // Something with types we cannot show. Store it as text of type names.
            if snapshot.items.isEmpty { return nil }
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let hasRich = PBType.richTypes.contains { snapshot.has($0) }

        // 4. Colors from text.
        if let parsed = ColorParser.parse(trimmed) {
            return Classification(kind: .color, title: parsed.hex, text: text, contentHash: hash(text), byteCount: byteCount, lineCount: 1, charCount: text.count, hasRich: false, colorHex: parsed.hex)
        }

        // 5. Links.
        if let url = linkURL(in: snapshot, text: trimmed) {
            let host = url.host?.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            return Classification(kind: .link, title: url.absoluteString, text: url.absoluteString, contentHash: hash("link:" + url.absoluteString), byteCount: byteCount, linkHost: host, lineCount: 1, charCount: url.absoluteString.count, hasRich: false)
        }

        // 6. Markdown and code.
        let md = MarkdownDetector.detect(text)
        let code = CodeDetector.detect(text)
        var kind: ClipKind = .text
        var language: String? = nil
        if md.score >= 6 && md.hasStructure {
            kind = .markdown
        } else if code.isCode && code.confidence >= 0.35 {
            kind = .code
            language = code.language
        } else if md.isMarkdown {
            kind = .markdown
        } else if hasRich && looksFormatted(snapshot) {
            kind = .richText
        } else if code.isCode {
            kind = .code
            language = code.language
        }
        // Rich text that is really code (editor copies with syntax color) stays code.

        let title = firstLine(of: trimmed)
        return Classification(kind: kind, title: title, text: text, contentHash: hash(text), byteCount: byteCount, language: language, lineCount: lineCount, charCount: text.count, hasRich: hasRich)
    }

    // MARK: Helpers

    static func hash(_ string: String) -> String { hash(Data(string.utf8)) }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func firstLine(of text: String) -> String {
        let line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? text
        let squashed = line.trimmingCharacters(in: .whitespaces)
        return String(squashed.prefix(200))
    }

    private static func filePaths(in snapshot: PasteboardSnapshot) -> [String] {
        var paths: [String] = []
        for item in snapshot.items {
            if let d = item[PBType.fileURL], let s = String(data: d, encoding: .utf8), let url = URL(string: s) {
                paths.append(url.path)
            }
        }
        if paths.isEmpty, let d = snapshot.data(for: PBType.legacyFilenames),
           let list = (try? PropertyListSerialization.propertyList(from: d, options: [], format: nil)) as? [String] {
            paths = list
        }
        return paths
    }

    private static func htmlOrRTFAsPlain(_ snapshot: PasteboardSnapshot) -> String? {
        if let d = snapshot.data(for: PBType.rtf), let a = NSAttributedString(rtf: d, documentAttributes: nil) { return a.string }
        if let d = snapshot.data(for: PBType.rtfd), let a = NSAttributedString(rtfd: d, documentAttributes: nil) { return a.string }
        if let d = snapshot.data(for: PBType.html), let a = NSAttributedString(html: d, options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) { return a.string }
        return nil
    }

    private static func linkURL(in snapshot: PasteboardSnapshot, text: String) -> URL? {
        if let d = snapshot.data(for: PBType.url), let s = String(data: d, encoding: .utf8), let url = URL(string: s), url.scheme != nil, url.scheme != "file" {
            return url
        }
        guard !text.contains("\n"), !text.contains(" "), text.count < 2048 else { return nil }
        let lower = text.lowercased()
        let schemes = ["http://", "https://", "ftp://", "mailto:", "x-callback-url://", "vscode://", "slack://", "notion://", "obsidian://", "zoommtg://"]
        guard schemes.contains(where: { lower.hasPrefix($0) }), let url = URL(string: text), url.host != nil || lower.hasPrefix("mailto:") else {
            // Bare domains like example.com/path count too.
            if let re = try? NSRegularExpression(pattern: #"^(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/\S*)?$"#, options: [.caseInsensitive]),
               re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil,
               let url = URL(string: "https://" + text), url.host != nil,
               text.contains("/") || text.hasPrefix("www.") {
                return url
            }
            return nil
        }
        return url
    }

    /// True when the rich types carry visible formatting beyond a single font.
    private static func looksFormatted(_ snapshot: PasteboardSnapshot) -> Bool {
        var attributed: NSAttributedString?
        if let d = snapshot.data(for: PBType.rtf) { attributed = NSAttributedString(rtf: d, documentAttributes: nil) }
        else if let d = snapshot.data(for: PBType.rtfd) { attributed = NSAttributedString(rtfd: d, documentAttributes: nil) }
        else if let d = snapshot.data(for: PBType.html) { attributed = NSAttributedString(html: d, options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) }
        guard let a = attributed, a.length > 0 else { return false }
        var fonts = Set<String>()
        var hasLink = false, hasList = false, hasAttachment = false
        a.enumerateAttributes(in: NSRange(location: 0, length: a.length)) { attrs, _, _ in
            if let f = attrs[.font] as? NSFont { fonts.insert("\(f.fontName)-\(f.pointSize)") }
            if attrs[.link] != nil { hasLink = true }
            if attrs[.attachment] != nil { hasAttachment = true }
            if let p = attrs[.paragraphStyle] as? NSParagraphStyle, !p.textLists.isEmpty { hasList = true }
        }
        return fonts.count > 1 || hasLink || hasList || hasAttachment
    }
}
