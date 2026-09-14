import AppKit
import Foundation
import UniformTypeIdentifiers

/// A file format the user can save a clip as.
struct ExportOption: Hashable, Identifiable {
    enum Kind: Hashable {
        case text, markdown, rtf, rtfd, html, image(ImageConversion.Format), webloc, code
    }
    let kind: Kind
    let title: String
    let fileExtension: String
    let utType: UTType

    var id: String { title + fileExtension }
}

/// What gets written to disk.
enum ExportPayload {
    case data(Data)
    case fileWrapper(FileWrapper)

    func write(to url: URL) throws {
        switch self {
        case .data(let d): try d.write(to: url, options: .atomic)
        case .fileWrapper(let w): try w.write(to: url, options: .atomic, originalContentsURL: nil)
        }
    }
}

/// Produces save-as options and file contents for a clip.
enum Exporter {
    static func options(for clip: Clip, snapshot: PasteboardSnapshot?) -> [ExportOption] {
        switch clip.kind {
        case .text:
            var list = [ExportOption(kind: .text, title: "Plain Text", fileExtension: "txt", utType: .plainText)]
            if clip.hasRich { list.append(contentsOf: richOptions(snapshot)) }
            return list
        case .markdown:
            var list = [ExportOption(kind: .markdown, title: "Markdown", fileExtension: "md", utType: UTType("net.daringfireball.markdown") ?? .plainText),
                        ExportOption(kind: .text, title: "Plain Text", fileExtension: "txt", utType: .plainText)]
            if clip.hasRich { list.append(contentsOf: richOptions(snapshot)) }
            return list
        case .code:
            let lang = CodeLanguage.named(clip.language)
            let ext = lang?.fileExtension ?? "txt"
            var list = [ExportOption(kind: .code, title: lang.map { "\($0.displayName) Source" } ?? "Source", fileExtension: ext, utType: UTType(filenameExtension: ext) ?? .sourceCode),
                        ExportOption(kind: .text, title: "Plain Text", fileExtension: "txt", utType: .plainText),
                        ExportOption(kind: .markdown, title: "Markdown (code block)", fileExtension: "md", utType: UTType("net.daringfireball.markdown") ?? .plainText)]
            if clip.hasRich { list.append(contentsOf: richOptions(snapshot)) }
            return list
        case .richText:
            var list: [ExportOption] = []
            list.append(ExportOption(kind: .markdown, title: "Markdown", fileExtension: "md", utType: UTType("net.daringfireball.markdown") ?? .plainText))
            list.append(contentsOf: richOptions(snapshot))
            list.append(ExportOption(kind: .text, title: "Plain Text", fileExtension: "txt", utType: .plainText))
            // Put the original format first.
            if let snapshot, snapshot.has(PBType.rtfd), let i = list.firstIndex(where: { $0.kind == .rtfd }) { list.insert(list.remove(at: i), at: 0) }
            else if let snapshot, snapshot.has(PBType.rtf), let i = list.firstIndex(where: { $0.kind == .rtf }) { list.insert(list.remove(at: i), at: 0) }
            else if let snapshot, snapshot.has(PBType.html), let i = list.firstIndex(where: { $0.kind == .html }) { list.insert(list.remove(at: i), at: 0) }
            return list
        case .image:
            let current = snapshot?.types.compactMap { ImageConversion.Format.from(pasteboardType: $0) }.first ?? .png
            var formats: [ImageConversion.Format] = [current]
            for f in [ImageConversion.Format.png, .jpeg, .tiff, .heic] where f != current { formats.append(f) }
            return formats.map { ExportOption(kind: .image($0), title: $0.displayName + ($0 == current ? " (original)" : ""), fileExtension: $0.fileExtension, utType: $0.utType) }
        case .link:
            return [ExportOption(kind: .webloc, title: "Web Location", fileExtension: "webloc", utType: UTType("com.apple.web-internet-location") ?? .data),
                    ExportOption(kind: .text, title: "Plain Text", fileExtension: "txt", utType: .plainText),
                    ExportOption(kind: .markdown, title: "Markdown Link", fileExtension: "md", utType: UTType("net.daringfireball.markdown") ?? .plainText)]
        case .color:
            return [ExportOption(kind: .text, title: "Plain Text", fileExtension: "txt", utType: .plainText)]
        case .files:
            return [ExportOption(kind: .text, title: "Paths as Text", fileExtension: "txt", utType: .plainText)]
        }
    }

    private static func richOptions(_ snapshot: PasteboardSnapshot?) -> [ExportOption] {
        var list: [ExportOption] = []
        if snapshot?.has(PBType.rtfd) == true {
            list.append(ExportOption(kind: .rtfd, title: "Rich Text with Attachments", fileExtension: "rtfd", utType: .rtfd))
        }
        list.append(ExportOption(kind: .rtf, title: "Rich Text", fileExtension: "rtf", utType: .rtf))
        list.append(ExportOption(kind: .html, title: "HTML", fileExtension: "html", utType: .html))
        return list
    }

    static func payload(for clip: Clip, snapshot: PasteboardSnapshot?, option: ExportOption) -> ExportPayload? {
        let attributed = snapshot.flatMap { RichTextConverter.attributedString(from: $0) }
        switch option.kind {
        case .text:
            let text = clip.kind == .files ? clip.filePaths.joined(separator: "\n") : (snapshot?.string ?? attributed?.string ?? clip.text)
            return .data(Data(text.utf8))
        case .code:
            return .data(Data((snapshot?.string ?? clip.text).utf8))
        case .markdown:
            switch clip.kind {
            case .richText:
                guard let attributed else { return .data(Data(clip.text.utf8)) }
                return .data(Data(RichTextConverter.markdown(from: attributed).utf8))
            case .code:
                let lang = CodeLanguage.named(clip.language)?.id ?? ""
                return .data(Data("```\(lang)\n\(clip.text)\n```\n".utf8))
            case .link:
                return .data(Data("[\(clip.linkTitle ?? clip.text)](\(clip.text))\n".utf8))
            default:
                return .data(Data((snapshot?.string ?? clip.text).utf8))
            }
        case .rtf:
            if let d = snapshot?.data(for: PBType.rtf) { return .data(d) }
            let a = attributed ?? NSAttributedString(string: clip.text)
            return RichTextConverter.rtfData(a).map { .data($0) }
        case .rtfd:
            if let d = snapshot?.data(for: PBType.rtfd), let wrapper = FileWrapper(serializedRepresentation: d) { return .fileWrapper(wrapper) }
            guard let attributed, let w = attributed.rtfdFileWrapper(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) else { return nil }
            return .fileWrapper(w)
        case .html:
            if let d = snapshot?.data(for: PBType.html) { return .data(d) }
            let a = attributed ?? NSAttributedString(string: clip.text)
            return RichTextConverter.htmlData(a).map { .data($0) }
        case .image(let format):
            guard let snapshot, let source = PBType.imageTypes.compactMap({ snapshot.data(for: $0) }).first else { return nil }
            if ImageConversion.Format.from(pasteboardType: snapshot.types.first { PBType.imageTypes.contains($0) } ?? "") == format {
                return .data(source)
            }
            return ImageConversion.convert(source, to: format).map { .data($0) }
        case .webloc:
            let plist: [String: String] = ["URL": clip.text]
            guard let d = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return nil }
            return .data(d)
        }
    }

    /// A safe default file name without extension.
    static func defaultFileName(for clip: Clip) -> String {
        var base: String
        switch clip.kind {
        case .image: base = "Image"
        case .link: base = clip.linkTitle ?? clip.linkHost ?? "Link"
        case .color: base = clip.colorHex ?? "Color"
        case .files: base = "Files"
        default: base = clip.title
        }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        base = base.replacingOccurrences(of: "[/:\\\\\\n\\r\\t]", with: "-", options: .regularExpression)
        base = base.replacingOccurrences(of: "[#`*_>|\\[\\]]", with: "", options: .regularExpression)
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: ". -"))
        if base.isEmpty { base = "Clip" }
        if base.count > 60 { base = String(base.prefix(60)).trimmingCharacters(in: .whitespaces) }
        let stamp = Self.stampFormatter.string(from: clip.createdAt)
        return clip.kind == .image || base == "Clip" ? "\(base) \(stamp)" : base
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()
}
