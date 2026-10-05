import Foundation

/// Prepares text for the regex-based detectors so that hostile input cannot
/// make them slow. Several patterns backtrack in proportion to the length of
/// a token or a line, so both are capped: real code and prose never have a
/// 300-character word or a 2,000-character line that matters for detection.
enum DetectionSample {
    static let maxCharacters = 20_000
    static let maxTokenLength = 256
    static let maxLineLength = 2_000

    /// A bounded copy of the text for detection only. Never used as content.
    static func make(_ text: String) -> String {
        let head = text.prefix(maxCharacters)
        var out = String()
        out.reserveCapacity(head.count)
        var lineLength = 0
        var tokenLength = 0
        for ch in head {
            if ch == "\n" {
                out.append(ch)
                lineLength = 0
                tokenLength = 0
                continue
            }
            lineLength += 1
            if lineLength > maxLineLength { continue }
            if ch == " " || ch == "\t" {
                tokenLength = 0
                out.append(ch)
                continue
            }
            tokenLength += 1
            if tokenLength > maxTokenLength { continue }
            out.append(ch)
        }
        return out
    }

    /// A wall-clock budget for a detector. Past the deadline the detector
    /// stops and reports "not detected", which is always safe.
    struct Budget {
        let deadline: Date
        init(seconds: TimeInterval) { deadline = Date().addingTimeInterval(seconds) }
        var isExpired: Bool { Date() > deadline }
    }
}
