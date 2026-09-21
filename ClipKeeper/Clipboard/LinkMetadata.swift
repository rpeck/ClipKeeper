import AppKit
import Foundation

/// Fetches a page title and favicon for a link clip.
enum LinkMetadata {
    struct Result {
        var title: String?
        var faviconData: Data?
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15 ClipKeeper/0.1"]
        return URLSession(configuration: config)
    }()

    static func fetch(_ url: URL) async -> Result {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return Result() }
        var result = Result()
        var iconURL: URL?
        if let (data, response) = try? await session.data(from: url), let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
            let head = String(bytes: data.prefix(400_000), encoding: .utf8) ?? String(bytes: data.prefix(400_000), encoding: .isoLatin1) ?? ""
            result.title = extractTitle(from: head)
            iconURL = extractIconURL(from: head, base: http.url ?? url)
        }
        if iconURL == nil, let host = url.host {
            iconURL = URL(string: "\(scheme)://\(host)/favicon.ico")
        }
        if let iconURL, let (data, response) = try? await session.data(from: iconURL),
           let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty, data.count < 2_000_000,
           NSImage(data: data) != nil {
            result.faviconData = data
        }
        return result
    }

    static func extractTitle(from html: String) -> String? {
        let patterns = [
            #"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']"#,
            #"<title[^>]*>([^<]{1,300})</title>"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators]),
               let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let r = Range(m.range(at: 1), in: html) {
                let raw = String(html[r])
                let decoded = decodeEntities(raw).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                if !decoded.isEmpty { return decoded }
            }
        }
        return nil
    }

    static func extractIconURL(from html: String, base: URL) -> URL? {
        guard let re = try? NSRegularExpression(pattern: #"<link[^>]+>"#, options: [.caseInsensitive]) else { return nil }
        var best: (score: Int, href: String)?
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(m.range, in: html) else { continue }
            let tag = String(html[r]).lowercased()
            guard let relRange = tag.range(of: #"rel=["']([^"']+)["']"#, options: .regularExpression),
                  let hrefRange = tag.range(of: #"href=["']([^"']+)["']"#, options: .regularExpression) else { continue }
            let rel = String(tag[relRange]).replacingOccurrences(of: #"rel=["']|["']$"#, with: "", options: .regularExpression)
            var href = String(tag[hrefRange]).replacingOccurrences(of: #"href=["']|["']$"#, with: "", options: .regularExpression)
            // Re-read href from the original case to keep the path intact.
            let original = String(html[r])
            if let hr = original.range(of: #"href=["']([^"']+)["']"#, options: [.regularExpression, .caseInsensitive]) {
                href = String(original[hr]).replacingOccurrences(of: #"(?i)href=["']|["']$"#, with: "", options: .regularExpression)
            }
            var score = 0
            if rel.contains("apple-touch-icon") {
                score = 3
            } else if rel.split(separator: " ").contains("icon") || rel.contains("shortcut icon") {
                score = 2
            } else {
                continue
            }
            if tag.contains("svg") { score -= 1 }
            if score > (best?.score ?? Int.min) { best = (score, href) }
        }
        guard let href = best?.href else { return nil }
        return URL(string: href, relativeTo: base)?.absoluteURL
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&ndash;": "–", "&mdash;": "—", "&hellip;": "…", "&copy;": "©", "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“"]
        for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
        if let re = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#) {
            let matches = re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed()
            for m in matches {
                guard let whole = Range(m.range, in: out), let hexFlag = Range(m.range(at: 1), in: out), let num = Range(m.range(at: 2), in: out) else { continue }
                let isHex = !out[hexFlag].isEmpty
                if let v = UInt32(out[num], radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(v) {
                    out.replaceSubrange(whole, with: String(Character(scalar)))
                }
            }
        }
        return out
    }
}
