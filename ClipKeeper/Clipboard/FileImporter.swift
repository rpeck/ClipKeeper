import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Turns files into pasteboard snapshots, so a file's contents become a clip
/// of the right kind: an image file becomes an image clip, a Markdown file a
/// Markdown clip, an RTF file a rich text clip, and so on.
enum FileImporter {
    /// The result of reading one file.
    struct Item {
        let url: URL
        let snapshot: PasteboardSnapshot
        let byteCount: Int
    }

    enum Problem: Error, LocalizedError {
        case unreadable(URL)
        case tooLarge(URL, Int)
        case unsupported(URL)

        var errorDescription: String? {
            switch self {
            case .unreadable(let u): return "Cannot read \(u.lastPathComponent)."
            case .tooLarge(let u, let n): return "\(u.lastPathComponent) is \(ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)), above the limit."
            case .unsupported(let u): return "\(u.lastPathComponent) is not a file type ClipKeeper can import."
            }
        }
    }

    /// Text files above this size need a confirmation before import.
    static let largeTextBytes = 5_000_000

    /// Expands folders one level deep and drops hidden files. Keeps the order.
    static func expand(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue, !isPackage(url) {
                let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isPackageKey], options: [.skipsHiddenFiles])) ?? []
                for child in children.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                    let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .isPackageKey])
                    if values?.isRegularFile == true || values?.isPackage == true { out.append(child) }
                }
            } else {
                out.append(url)
            }
        }
        return out
    }

    private static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
    }

    static func contentType(of url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: url.pathExtension)
    }

    /// Reads one file into a snapshot. `imageLimit` is the byte limit for
    /// images, or nil for no limit.
    static func read(_ url: URL, imageLimit: Int?) throws -> Item {
        guard let type = contentType(of: url) else { throw Problem.unsupported(url) }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        if type.conforms(to: .image) {
            if let imageLimit, size > imageLimit { throw Problem.tooLarge(url, size) }
            guard let data = try? Data(contentsOf: url) else { throw Problem.unreadable(url) }
            let pbType: String
            if type.conforms(to: .png) { pbType = PBType.png } else if type.conforms(to: .jpeg) { pbType = PBType.jpeg } else if type.conforms(to: .tiff) { pbType = PBType.tiff } else if type.conforms(to: .heic) { pbType = PBType.heic } else if type.conforms(to: .gif) { pbType = PBType.gif } else {
                // Other image formats are converted to PNG so the clip can paste anywhere.
                guard let png = ImageConversion.convert(data, to: .png) else { throw Problem.unsupported(url) }
                return Item(url: url, snapshot: .image(png: png), byteCount: png.count)
            }
            return Item(url: url, snapshot: PasteboardSnapshot(items: [[pbType: data]]), byteCount: data.count)
        }

        if type.conforms(to: .rtfd) || type == UTType("com.apple.rtfd") {
            guard let wrapper = try? FileWrapper(url: url), let attributed = NSAttributedString(rtfdFileWrapper: wrapper, documentAttributes: nil) else { throw Problem.unreadable(url) }
            return Item(url: url, snapshot: richSnapshot(attributed, rtfd: wrapper.serializedRepresentation), byteCount: size)
        }
        if type.conforms(to: .rtf) {
            guard let data = try? Data(contentsOf: url), let attributed = NSAttributedString(rtf: data, documentAttributes: nil) else { throw Problem.unreadable(url) }
            var snap = richSnapshot(attributed, rtfd: nil)
            snap.items[0][PBType.rtf] = data
            return Item(url: url, snapshot: snap, byteCount: size)
        }
        if type.conforms(to: .html) {
            guard let data = try? Data(contentsOf: url),
                  let attributed = NSAttributedString(html: data, options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) else { throw Problem.unreadable(url) }
            var snap = richSnapshot(attributed, rtfd: nil)
            snap.items[0][PBType.html] = data
            return Item(url: url, snapshot: snap, byteCount: size)
        }
        if type.conforms(to: .pdf) {
            guard let doc = PDFDocument(url: url), let text = doc.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Problem.unreadable(url) }
            return Item(url: url, snapshot: .plainText(text), byteCount: text.utf8.count)
        }
        if let word = UTType("org.openxmlformats.wordprocessingml.document"), type.conforms(to: word) {
            guard let attributed = try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil) else { throw Problem.unreadable(url) }
            return Item(url: url, snapshot: richSnapshot(attributed, rtfd: nil), byteCount: size)
        }

        // Everything else that is text: plain, Markdown, source code, JSON, YAML, CSV, logs…
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) || type.conforms(to: .yaml) || type.conforms(to: .propertyList) || looksLikeText(url) {
            guard let data = try? Data(contentsOf: url) else { throw Problem.unreadable(url) }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw Problem.unsupported(url) }
            return Item(url: url, snapshot: .plainText(text), byteCount: data.count)
        }
        throw Problem.unsupported(url)
    }

    /// A rich snapshot carries RTF plus the plain text, so the classifier
    /// and the paste both work.
    private static func richSnapshot(_ attributed: NSAttributedString, rtfd: Data?) -> PasteboardSnapshot {
        var dict: [String: Data] = [PBType.string: Data(attributed.string.utf8)]
        if let rtf = RichTextConverter.rtfData(attributed) { dict[PBType.rtf] = rtf }
        if let rtfd { dict[PBType.rtfd] = rtfd }
        return PasteboardSnapshot(items: [dict])
    }

    /// Files without a known type are text when their first bytes decode as UTF-8 without NULs.
    private static func looksLikeText(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4096)) ?? Data()
        guard !head.isEmpty, !head.contains(0) else { return false }
        return String(data: head, encoding: .utf8) != nil
    }
}

/// Imports files into the store, with the user-facing policy: order,
/// confirmations, limits, and the summary toast.
@MainActor
final class ImportCoordinator {
    let store: ClipStore
    let prefs: Preferences

    struct Outcome {
        var imported: [Clip] = []
        var problems: [String] = []
        var cancelled = false

        var summary: String {
            if cancelled { return "Import cancelled" }
            var parts: [String] = []
            if !imported.isEmpty { parts.append(imported.count == 1 ? "Imported 1 file" : "Imported \(imported.count) files") }
            if !problems.isEmpty { parts.append(problems.count == 1 ? "1 skipped" : "\(problems.count) skipped") }
            return parts.isEmpty ? "Nothing to import" : parts.joined(separator: " · ")
        }
    }

    init(store: ClipStore, prefs: Preferences = .shared) {
        self.store = store
        self.prefs = prefs
    }

    /// Imports the files as separate clips. The first file ends on top. When
    /// `set` is a collection, the clips move there. Large text files ask once.
    func importFiles(_ urls: [URL], into set: ClipSet? = nil) -> Outcome {
        var outcome = Outcome()
        let files = FileImporter.expand(urls)
        guard !files.isEmpty else { return outcome }

        // Large text files: one confirmation for all of them.
        let large = files.filter { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let isImage = FileImporter.contentType(of: url)?.conforms(to: .image) ?? false
            return !isImage && size > FileImporter.largeTextBytes
        }
        if !large.isEmpty, !confirmLarge(large) {
            outcome.cancelled = true
            return outcome
        }

        var items: [FileImporter.Item] = []
        for url in files {
            do {
                items.append(try FileImporter.read(url, imageLimit: prefs.imageByteLimit))
            } catch {
                outcome.problems.append(error.localizedDescription)
            }
        }

        // Ingest last to first, so the first file is the newest and sits on top.
        var clips: [Clip] = []
        for item in items.reversed() {
            if let clip = store.ingest(item.snapshot, sourceBundleID: "com.apple.finder", sourceAppName: "Finder", title: item.url.lastPathComponent, sourcePath: item.url.path) {
                clips.insert(clip, at: 0)
            }
        }
        if let set, set.collectionID != nil, !clips.isEmpty {
            store.move(clips, to: set)
        }
        outcome.imported = clips
        return outcome
    }

    private func confirmLarge(_ urls: [URL]) -> Bool {
        let alert = NSAlert()
        alert.messageText = urls.count == 1 ? "Import a large file?" : "Import \(urls.count) large files?"
        let names = urls.prefix(5).map { "\($0.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: Int64((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), countStyle: .file)))" }
        alert.informativeText = names.joined(separator: "\n") + (urls.count > 5 ? "\nand \(urls.count - 5) more" : "") + "\n\nEach becomes a clip with the whole text."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
