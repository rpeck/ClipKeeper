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
    }

    static func == (lhs: Clip, rhs: Clip) -> Bool { lhs.uuid == rhs.uuid && lhs.updatedAt == rhs.updatedAt && lhs.pinned == rhs.pinned && lhs.linkTitle == rhs.linkTitle && lhs.collectionID == rhs.collectionID }
    func hash(into hasher: inout Hasher) { hasher.combine(uuid) }
}

extension Clip {
    var isInHistory: Bool { collectionID == nil }

    /// A one-line summary shown under the preview, like "40 lines · 1545 characters".
    var metaSummary: String {
        switch kind {
        case .image:
            var parts: [String] = []
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

    var filePaths: [String] {
        guard kind == .files else { return [] }
        return text.split(separator: "\n").map(String.init)
    }
}
