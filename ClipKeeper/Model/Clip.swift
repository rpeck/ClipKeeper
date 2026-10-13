import Foundation
import GRDB

/// One clipboard capture. Metadata lives in SQLite. The full pasteboard
/// snapshot lives in a blob file keyed by `uuid`.
struct Clip: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "clip"

    var id: Int64?
    var uuid: String
    var createdAt: Date
    var updatedAt: Date
    var kind: ClipKind
    /// Short display title: the first non-empty line, the link title, or a file name.
    var title: String
    /// Main text content. Full text for text kinds, the URL for links, the hex
    /// value for colors, the paths for files, and an empty string for images.
    var text: String
    var contentHash: String
    var byteCount: Int
    var sourceBundleID: String?
    var sourceAppName: String?
    var pinned: Bool
    /// `nil` means History. Otherwise the uuid of a collection.
    var collectionID: String?
    /// Ordering inside a collection. Higher is nearer the top.
    var position: Double
    var language: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var linkTitle: String?
    var linkHost: String?
    var lineCount: Int
    var charCount: Int
    var hasRich: Bool
    var colorHex: String?
    /// The formats the source app put on the clipboard, for display: "PNG, TIFF".
    var formats: String?
    /// For clips imported from a file: the path of that file.
    var sourcePath: String?
    /// "network" for a clip received from another device. It never fetches a
    /// link title, and it never replaces a local clip in the duplicate check.
    var origin: String?
    /// The device a clip came from, when `origin` is set: a paired device's
    /// name for a transfer, or "Another Apple device" for Universal Clipboard.
    var sourceDevice: String?
    /// The paired device's id for a transfer. Stays the same after a rename.
    var sourceDeviceID: String?
    /// Possible personal or secret data found in the text: a
    /// PersonalDataFlags bit mask. Nil: not scanned yet.
    var piiFlags: Int?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let uuid = Column(CodingKeys.uuid)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
        static let kind = Column(CodingKeys.kind)
        static let contentHash = Column(CodingKeys.contentHash)
        static let pinned = Column(CodingKeys.pinned)
        static let collectionID = Column(CodingKeys.collectionID)
        static let position = Column(CodingKeys.position)
        static let byteCount = Column(CodingKeys.byteCount)
        static let origin = Column(CodingKeys.origin)
        static let sourceDevice = Column(CodingKeys.sourceDevice)
        static let sourceDeviceID = Column(CodingKeys.sourceDeviceID)
        static let piiFlags = Column(CodingKeys.piiFlags)
    }

    /// A ClipKeeper or LocalSend transfer.
    static let networkOrigin = "network"
    /// Universal Clipboard (Handoff) from another device on the Apple Account.
    static let handoffOrigin = "handoff"
    static let handoffDeviceName = "Another Apple device"

    static func == (lhs: Clip, rhs: Clip) -> Bool { lhs.uuid == rhs.uuid && lhs.updatedAt == rhs.updatedAt && lhs.pinned == rhs.pinned && lhs.linkTitle == rhs.linkTitle && lhs.collectionID == rhs.collectionID }
    func hash(into hasher: inout Hasher) { hasher.combine(uuid) }
}

extension Clip {
    var isInHistory: Bool { collectionID == nil }

    /// True for a clip that arrived through a transfer.
    var isFromNetwork: Bool { origin == Clip.networkOrigin }

    /// True for a clip that came through Universal Clipboard.
    var isFromHandoff: Bool { origin == Clip.handoffOrigin }

    var personalData: PersonalDataFlags { PersonalDataFlags(rawValue: piiFlags ?? 0) }

    /// True for any clip that did not start on this Mac.
    var isFromOtherDevice: Bool { origin != nil }

    /// "Pixel", "Work Mac", or "Another Apple device"; nil for this Mac.
    var sourceDeviceName: String? {
        guard isFromOtherDevice else { return nil }
        return sourceDevice ?? (isFromHandoff ? Clip.handoffDeviceName : sourceAppName)
    }

    /// A one-line summary shown under the preview, like "40 lines · 1545 characters".
    var metaSummary: String {
        switch kind {
        case .image:
            var parts: [String] = []
            if let first = formats?.split(separator: ",").first { parts.append(first.trimmingCharacters(in: .whitespaces)) }
            if let w = imageWidth, let h = imageHeight { parts.append("\(w) × \(h)") }
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
            return parts.joined(separator: " · ")
        case .link:
            return linkHost ?? text
        case .color:
            return colorHex.flatMap { ColorParser.parse($0)?.rgbString } ?? "Color"
        case .files:
            let n = text.split(separator: "\n").count
            return n == 1 ? "1 file" : "\(n) files"
        case .text, .markdown, .code, .richText:
            var parts: [String] = []
            if lineCount > 1 { parts.append(lineCount == 1 ? "1 line" : "\(lineCount) lines") }
            parts.append(charCount == 1 ? "1 character" : "\(charCount) characters")
            if kind == .code, let language { parts.append(CodeLanguage.named(language)?.displayName ?? language) }
            return parts.joined(separator: " · ")
        }
    }

    /// Multi-line details for the ⓘ tooltip on a card.
    var detailsTooltip: String {
        var lines: [String] = []
        var typeLine = "Type: \(kind.displayName)"
        if kind == .code, let language { typeLine += " (\(CodeLanguage.named(language)?.displayName ?? language))" }
        if hasRich, kind != .richText { typeLine += ", with rich text" }
        lines.append(typeLine)
        if let formats, !formats.isEmpty { lines.append("On the clipboard as: \(formats)") }
        switch kind {
        case .image:
            if let w = imageWidth, let h = imageHeight { lines.append("Size: \(w) × \(h) pixels") }
        case .link:
            if let linkTitle { lines.append("Title: \(linkTitle)") }
            if let linkHost { lines.append("Site: \(linkHost)") }
        case .color:
            if let colorHex, let parsed = ColorParser.parse(colorHex) { lines.append("Color: \(parsed.hex) · \(parsed.rgbString)") }
        case .files:
            lines.append(filePaths.count == 1 ? "1 file" : "\(filePaths.count) files")
        default:
            lines.append("Length: \(lineCount == 1 ? "1 line" : "\(lineCount) lines"), \(charCount == 1 ? "1 character" : "\(charCount) characters")")
        }
        lines.append("Stored: \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))")
        if let sourcePath { lines.append("File: \(sourcePath)") }
        if !personalData.isEmpty { lines.append("Possible personal data: \(personalData.names)") }
        if isFromNetwork {
            lines.append("Received over the local network from: \(sourceDeviceName ?? "another device")")
        } else if isFromHandoff {
            lines.append("From another Apple device on your Apple Account (Universal Clipboard)")
        } else if let sourceAppName {
            lines.append("Copied from: \(sourceAppName)")
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        lines.append("Copied: \(f.string(from: createdAt))")
        if pinned { lines.append("Pinned") }
        return lines.joined(separator: "\n")
    }

    var filePaths: [String] {
        guard kind == .files else { return [] }
        return text.split(separator: "\n").map(String.init)
    }
}
