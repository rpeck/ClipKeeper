import AppKit
import Foundation

/// A color parsed from text or from the pasteboard, in sRGB.
struct ParsedColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var hex: String {
        let r = Int((red * 255).rounded()), g = Int((green * 255).rounded()), b = Int((blue * 255).rounded())
        if alpha < 0.999 {
            let a = Int((alpha * 255).rounded())
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var rgbString: String {
        let r = Int((red * 255).rounded()), g = Int((green * 255).rounded()), b = Int((blue * 255).rounded())
        if alpha < 0.999 {
            return "rgba(\(r), \(g), \(b), \(String(format: "%.2f", alpha)))"
        }
        return "rgb(\(r), \(g), \(b))"
    }

    var swiftString: String {
        String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", red, green, blue)
    }

    var cssString: String { hex.lowercased() }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init?(nsColor: NSColor) {
        guard let c = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent), alpha: Double(c.alphaComponent))
    }
}

/// Recognizes color literals in text: `#RGB`, `#RRGGBB`, `#RRGGBBAA`,
/// `rgb(r, g, b)`, `rgba(r, g, b, a)`, and `hsl(h, s%, l%)`.
enum ColorParser {
    static func parse(_ raw: String) -> ParsedColor? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 40, !s.contains("\n") else { return nil }
        if let c = parseHex(s) { return c }
        if let c = parseRGB(s) { return c }
        if let c = parseHSL(s) { return c }
        return nil
    }

    private static func parseHex(_ s: String) -> ParsedColor? {
        guard s.hasPrefix("#") else { return nil }
        let hex = String(s.dropFirst())
        guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        func comp(_ str: Substring) -> Double? {
            guard let v = Int(str, radix: 16) else { return nil }
            return Double(v) / 255.0
        }
        switch hex.count {
        case 3, 4:
            let chars = Array(hex)
            let expanded = chars.map { String(repeating: $0, count: 2) }.joined()
            return parseHex("#" + expanded)
        case 6:
            guard let r = comp(hex.prefix(2)), let g = comp(hex.dropFirst(2).prefix(2)), let b = comp(hex.dropFirst(4).prefix(2)) else { return nil }
            return ParsedColor(red: r, green: g, blue: b)
        case 8:
            guard let r = comp(hex.prefix(2)), let g = comp(hex.dropFirst(2).prefix(2)),
                  let b = comp(hex.dropFirst(4).prefix(2)), let a = comp(hex.dropFirst(6).prefix(2)) else { return nil }
            return ParsedColor(red: r, green: g, blue: b, alpha: a)
        default:
            return nil
        }
    }

    private static func numbers(in body: String) -> [Double]? {
        let parts = body.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var values: [Double] = []
        for p in parts {
            var t = p
            var isPercent = false
            if t.hasSuffix("%") { isPercent = true; t.removeLast() }
            guard let v = Double(t) else { return nil }
            values.append(isPercent ? v / 100.0 * 255.0 : v)
        }
        return values
    }

    private static func parseRGB(_ s: String) -> ParsedColor? {
        let lower = s.lowercased()
        guard lower.hasPrefix("rgb(") || lower.hasPrefix("rgba("), lower.hasSuffix(")") else { return nil }
        let start = lower.index(after: lower.firstIndex(of: "(")!)
        let body = String(lower[start..<lower.index(before: lower.endIndex)])
        guard let nums = numbers(in: body), nums.count == 3 || nums.count == 4 else { return nil }
        let r = nums[0], g = nums[1], b = nums[2]
        guard (0...255).contains(r), (0...255).contains(g), (0...255).contains(b) else { return nil }
        var a = 1.0
        if nums.count == 4 {
            // Percent alpha was scaled to 0–255 above; a plain alpha is 0–1.
            a = nums[3] > 1 ? nums[3] / 255.0 : nums[3]
            guard (0...1).contains(a) else { return nil }
        }
        return ParsedColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func parseHSL(_ s: String) -> ParsedColor? {
        let lower = s.lowercased()
        guard lower.hasPrefix("hsl(") || lower.hasPrefix("hsla("), lower.hasSuffix(")") else { return nil }
        let start = lower.index(after: lower.firstIndex(of: "(")!)
        let body = String(lower[start..<lower.index(before: lower.endIndex)])
        let parts = body.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        guard let h = Double(parts[0].replacingOccurrences(of: "deg", with: "")),
              let sat = Double(parts[1].replacingOccurrences(of: "%", with: "")),
              let light = Double(parts[2].replacingOccurrences(of: "%", with: "")) else { return nil }
        var a = 1.0
        if parts.count == 4 {
            var t = parts[3]
            let pct = t.hasSuffix("%")
            if pct { t.removeLast() }
            guard let v = Double(t) else { return nil }
            a = pct ? v / 100 : v
        }
        let c = NSColor(hue: (h.truncatingRemainder(dividingBy: 360)) / 360, saturation: sat / 100, brightness: 0, alpha: a)
        _ = c
        // Convert HSL to RGB directly.
        let sN = sat / 100, lN = light / 100
        let chroma = (1 - abs(2 * lN - 1)) * sN
        let hp = (h.truncatingRemainder(dividingBy: 360)) / 60
        let x = chroma * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        var r = 0.0, g = 0.0, b = 0.0
        switch hp {
        case 0..<1: (r, g, b) = (chroma, x, 0)
        case 1..<2: (r, g, b) = (x, chroma, 0)
        case 2..<3: (r, g, b) = (0, chroma, x)
        case 3..<4: (r, g, b) = (0, x, chroma)
        case 4..<5: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        let m = lN - chroma / 2
        return ParsedColor(red: r + m, green: g + m, blue: b + m, alpha: a)
    }
}
