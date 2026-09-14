import Foundation
import GRDB

/// A named, user-managed set of clips. History is not a collection; it is
/// the set of clips whose `collectionID` is nil.
struct ClipCollection: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "collection"

    var id: Int64?
    var uuid: String
    var name: String
    var sortOrder: Int
    var createdAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let uuid = Column(CodingKeys.uuid)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }
}

/// A tab in the shelf. The first tab is always History.
enum ClipSet: Hashable, Identifiable {
    case history
    case collection(ClipCollection)

    var id: String {
        switch self {
        case .history: return "history"
        case .collection(let c): return c.uuid
        }
    }

    var name: String {
        switch self {
        case .history: return "History"
        case .collection(let c): return c.name
        }
    }

    var collectionID: String? {
        switch self {
        case .history: return nil
        case .collection(let c): return c.uuid
        }
    }
}
