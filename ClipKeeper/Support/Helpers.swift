import AppKit
import Foundation
import SwiftUI

/// Icons for source apps, cached by bundle identifier.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        cache[bundleID] = icon
        return icon
    }

    static func icon(forFilePath path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }
}

/// Short relative times: "now", "4m", "2h", "3d", or a date.
enum RelativeTime {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if seconds < 86_400 * 7 { return "\(Int(seconds / 86_400))d" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: date)
    }
}

/// Caches thumbnails and rich text so rows render fast while scrolling.
@MainActor
final class RenderCache {
    static let shared = RenderCache()
    private let images = NSCache<NSString, NSImage>()
    private let attributed = NSCache<NSString, NSAttributedString>()

    private init() {
        images.countLimit = 300
        attributed.countLimit = 300
    }

    func thumbnail(for clip: Clip, store: ClipStore) -> NSImage? {
        let key = clip.uuid as NSString
        if let img = images.object(forKey: key) { return img }
        guard let img = store.blobs.thumbnail(for: clip.uuid) else { return nil }
        images.setObject(img, forKey: key)
        return img
    }

    func fullImage(for clip: Clip, store: ClipStore) -> NSImage? {
        let key = (clip.uuid + "-full") as NSString
        if let img = images.object(forKey: key) { return img }
        guard let snap = store.snapshot(for: clip), let data = PBType.imageTypes.compactMap({ snap.data(for: $0) }).first, let img = NSImage(data: data) else { return nil }
        images.setObject(img, forKey: key)
        return img
    }

    func richText(for clip: Clip, store: ClipStore) -> NSAttributedString? {
        let key = (clip.uuid + "-rich") as NSString
        if let a = attributed.object(forKey: key) { return a }
        guard let snap = store.snapshot(for: clip), let a = RichTextConverter.attributedString(from: snap) else { return nil }
        let prepared = RichTextDisplay.prepared(a)
        attributed.setObject(prepared, forKey: key)
        return prepared
    }

    func invalidate(uuid: String) {
        images.removeObject(forKey: uuid as NSString)
        images.removeObject(forKey: (uuid + "-full") as NSString)
        attributed.removeObject(forKey: (uuid + "-rich") as NSString)
    }
}

/// Makes pasted rich text readable in both light and dark appearance by
/// removing plain black-on-white colors, which are defaults, not choices.
enum RichTextDisplay {
    static func prepared(_ source: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: m.length)
        m.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            guard let c = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            let isNeutral = abs(c.redComponent - c.greenComponent) < 0.08 && abs(c.greenComponent - c.blueComponent) < 0.08
            if isNeutral, c.brightnessComponent < 0.25 || c.brightnessComponent > 0.9 {
                m.removeAttribute(.foregroundColor, range: range)
            }
        }
        m.enumerateAttribute(.backgroundColor, in: full) { value, range, _ in
            guard let c = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            if c.brightnessComponent > 0.9 || c.alphaComponent < 0.05 {
                m.removeAttribute(.backgroundColor, range: range)
            }
        }
        m.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        // Re-apply real colors that were kept.
        source.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            guard let c = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            let isNeutral = abs(c.redComponent - c.greenComponent) < 0.08 && abs(c.greenComponent - c.blueComponent) < 0.08
            if !(isNeutral && (c.brightnessComponent < 0.25 || c.brightnessComponent > 0.9)) {
                m.addAttribute(.foregroundColor, value: c, range: range)
            }
        }
        return m
    }
}

/// Lays out children in rows, wrapping when they do not fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 { x = 0; y += rowHeight + rowSpacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + rowSpacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
