import Foundation

/// Which clips the shelf shows, besides the set and the search text.
struct ClipFilter: Hashable {
    enum Source: Hashable {
        case all
        /// Copied on this Mac.
        case thisMac
        /// From any other device: transfers and Universal Clipboard.
        case otherDevices
        /// From one source, as listed by `ClipStore.sourceSummaries()`.
        case device(SourceKey)
        /// From devices whose name contains this text: the `from:` search word.
        case deviceNamed(String)
    }

    var source: Source = .all
    /// Only clips with possible personal data.
    var personalOnly = false

    var isActive: Bool { source != .all || personalOnly }

    /// This filter with the search words on top: a `from:` word replaces the
    /// source, and `has:personal` adds the personal-data condition.
    func adding(_ words: ClipFilter) -> ClipFilter {
        var result = self
        if words.source != .all { result.source = words.source }
        result.personalOnly = personalOnly || words.personalOnly
        return result
    }
}

/// One source of clips: a paired device (by id), a device known only by name,
/// or Universal Clipboard.
struct SourceKey: Hashable {
    var origin: String
    var deviceID: String?
    var deviceName: String?
}

/// One row of the audit: who sent clips, how many, when, and what.
struct SourceSummary: Identifiable, Hashable {
    var key: SourceKey
    var name: String
    var count: Int
    var personalCount: Int
    var first: Date
    var last: Date
    var kinds: [ClipKind]

    var id: SourceKey { key }
    var isHandoff: Bool { key.origin == Clip.handoffOrigin }
}

/// Search words that filter instead of match: `from:other`, `from:this`,
/// `from:<device name>`, and `has:personal`. The rest is the search text.
enum SearchTokens {
    static func parse(_ query: String) -> (text: String, filter: ClipFilter) {
        var filter = ClipFilter()
        var words: [Substring] = []
        for word in query.split(separator: " ", omittingEmptySubsequences: true) {
            let lower = word.lowercased()
            if lower.hasPrefix("from:") {
                let value = String(lower.dropFirst(5))
                switch value {
                case "": continue
                case "other", "others", "elsewhere", "devices": filter.source = .otherDevices
                case "this", "here", "local", "me": filter.source = .thisMac
                default: filter.source = .deviceNamed(value)
                }
            } else if lower == "has:personal" || lower == "has:pii" || lower == "is:flagged" {
                filter.personalOnly = true
            } else {
                words.append(word)
            }
        }
        return (words.joined(separator: " "), filter)
    }
}
