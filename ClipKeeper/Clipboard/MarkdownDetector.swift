import Foundation

/// Scores how much a piece of text looks like Markdown.
enum MarkdownDetector {
    struct Result {
        var score: Double
        var hasStructure: Bool   // headings, fences, links, or tables
        var isMarkdown: Bool { score >= 4 }
    }

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        compileRegex(pattern: pattern, options: options)
    }

    private static let heading = regex(#"^#{1,6} \S"#)
    private static let fence = regex(#"^\s*(```|~~~)"#)
    private static let listLine = regex(#"^\s{0,6}([-*+]|\d+[.)]) \S"#)
    private static let link = regex(#"\[[^\]\n]+\]\((https?://|/|\.|#)[^)\s]*\)"#)
    private static let image = regex(#"!\[[^\]\n]*\]\([^)\s]+\)"#)
    private static let strong = regex(#"(\*\*|__)[^*_\n]{1,80}\1"#)
    private static let emphasis = regex(#"(?<![\w*])(\*|_)[^*_\n]{1,60}\1(?![\w*])"#)
    private static let quote = regex(#"^> \S"#)
    private static let tableRow = regex(#"^\|.*\|\s*$"#)
    private static let tableSep = regex(#"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$"#)
    private static let inlineCode = regex(#"`[^`\n]{1,80}`"#)
    private static let rule = regex(#"^(-{3,}|\*{3,}|_{3,})\s*$"#)
    private static let setext = regex(#"^\S.{0,120}\n(={3,}|-{3,})\s*$"#)
    private static let taskItem = regex(#"^\s*[-*+] \[( |x|X)\] "#)

    private static func count(_ re: NSRegularExpression, in text: String) -> Int {
        re.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func detect(_ text: String) -> Result {
        // Detection runs on a bounded sample: long tokens and lines are cut, which
        // keeps every pattern below linear time on hostile input.
        let trimmed = DetectionSample.make(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return Result(score: 0, hasStructure: false) }

        var score = 0.0
        var structure = false

        let headings = count(heading, in: trimmed)
        if headings > 0 { score += min(6, Double(headings) * 3); structure = true }

        let fences = count(fence, in: trimmed)
        if fences >= 2 { score += 4; structure = true } else if fences == 1 { score += 1 }

        let lists = count(listLine, in: trimmed)
        switch lists {
        case 0, 1: break
        case 2: score += 2
        case 3, 4: score += 3
        default: score += 4
        }

        let links = count(link, in: trimmed)
        if links > 0 { score += min(4, Double(links) * 2); structure = true }
        let images = count(image, in: trimmed)
        if images > 0 { score += min(4, Double(images) * 2); structure = true }

        score += min(4, Double(count(strong, in: trimmed)) * 2)
        score += min(2, Double(count(emphasis, in: trimmed)))
        score += min(4, Double(count(quote, in: trimmed)) * 2)

        if count(tableRow, in: trimmed) >= 2, count(tableSep, in: trimmed) >= 1 { score += 4; structure = true }

        score += min(3, Double(count(inlineCode, in: trimmed)))
        score += min(1, Double(count(rule, in: trimmed)))
        score += min(2, Double(count(setext, in: trimmed)) * 2)
        score += min(3, Double(count(taskItem, in: trimmed)) * 1.5)

        return Result(score: score, hasStructure: structure)
    }
}
