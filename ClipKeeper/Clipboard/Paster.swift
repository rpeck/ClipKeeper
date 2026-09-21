import AppKit
import Carbon.HIToolbox
import Foundation

/// A representation the user can paste a clip as.
enum PasteVariant: Hashable, Identifiable {
    case original
    case plainText
    case markdown
    case html
    case image(ImageConversion.Format)
    case url
    case linkTitle
    case markdownLink
    case colorHex
    case colorRGB
    case colorSwift
    case colorCSS
    case filePaths

    var id: String { title }

    var title: String {
        switch self {
        case .original: return "Original"
        case .plainText: return "Plain Text"
        case .markdown: return "Markdown"
        case .html: return "HTML"
        case .image(let f): return f.displayName
        case .url: return "URL"
        case .linkTitle: return "Title"
        case .markdownLink: return "Markdown Link"
        case .colorHex: return "Hex"
        case .colorRGB: return "rgb()"
        case .colorSwift: return "SwiftUI Color"
        case .colorCSS: return "CSS"
        case .filePaths: return "Paths as Text"
        }
    }

    /// The variants that make sense for a clip, in menu order. The first is the default.
    static func variants(for clip: Clip, snapshot: PasteboardSnapshot?) -> [PasteVariant] {
        switch clip.kind {
        case .text:
            return [.original]
        case .markdown, .code:
            return clip.hasRich ? [.original, .plainText] : [.original]
        case .richText:
            return [.original, .plainText, .markdown, .html]
        case .image:
            let current = snapshot?.types.compactMap { ImageConversion.Format.from(pasteboardType: $0) }.first
            var list: [PasteVariant] = [.original]
            for f in [ImageConversion.Format.png, .jpeg, .tiff] where f != current { list.append(.image(f)) }
            return list
        case .link:
            var list: [PasteVariant] = [.original, .url]
            if clip.linkTitle != nil { list.append(.linkTitle); list.append(.markdownLink) }
            return list
        case .color:
            return [.original, .colorHex, .colorRGB, .colorCSS, .colorSwift]
        case .files:
            return [.original, .filePaths]
        }
    }
}

/// Writes clips to the pasteboard and sends ⌘V to the front app.
@MainActor
final class Paster {
    static let shared = Paster()

    /// The change count of the last write ClipKeeper made. The monitor skips it.
    private(set) var lastWrittenChangeCount: Int = -1

    private var bundleID: String { Bundle.main.bundleIdentifier ?? "com.raymondpeck.ClipKeeper" }

    /// Builds the snapshot for a variant.
    func snapshot(for clip: Clip, variant: PasteVariant, original: PasteboardSnapshot?) -> PasteboardSnapshot? {
        switch variant {
        case .original:
            return original ?? PasteboardSnapshot.plainText(clip.text)
        case .plainText:
            let text = original?.string ?? RichTextConverter.attributedString(from: original ?? PasteboardSnapshot(items: []))?.string ?? clip.text
            return .plainText(text)
        case .markdown:
            guard let original, let a = RichTextConverter.attributedString(from: original) else { return .plainText(clip.text) }
            return .plainText(RichTextConverter.markdown(from: a))
        case .html:
            guard let original else { return .plainText(clip.text) }
            if let d = original.data(for: PBType.html), let s = String(data: d, encoding: .utf8) { return .plainText(s) }
            guard let a = RichTextConverter.attributedString(from: original), let d = RichTextConverter.htmlData(a) else { return .plainText(clip.text) }
            return .plainText(String(bytes: d, encoding: .utf8) ?? clip.text)
        case .image(let format):
            guard let original, let source = PBType.imageTypes.compactMap({ original.data(for: $0) }).first,
                  let converted = ImageConversion.convert(source, to: format) else { return original }
            return PasteboardSnapshot(items: [[format.pasteboardType: converted]])
        case .url:
            return .plainText(clip.text)
        case .linkTitle:
            return .plainText(clip.linkTitle ?? clip.text)
        case .markdownLink:
            return .plainText("[\(clip.linkTitle ?? clip.text)](\(clip.text))")
        case .colorHex, .colorRGB, .colorSwift, .colorCSS:
            guard let hex = clip.colorHex, let parsed = ColorParser.parse(hex) else { return .plainText(clip.text) }
            let text: String
            switch variant {
            case .colorHex: text = parsed.hex
            case .colorRGB: text = parsed.rgbString
            case .colorSwift: text = parsed.swiftString
            default: text = parsed.cssString
            }
            return .color(parsed.nsColor, text: text)
        case .filePaths:
            return .plainText(clip.filePaths.joined(separator: "\n"))
        }
    }

    /// Puts the clip on the pasteboard. Returns false when nothing could be written.
    @discardableResult
    func copy(clip: Clip, variant: PasteVariant, original: PasteboardSnapshot?) -> Bool {
        guard let snap = snapshot(for: clip, variant: variant, original: original) else { return false }
        lastWrittenChangeCount = snap.write(to: .general, markSource: bundleID)
        return true
    }

    /// Sends ⌘V to the front application. Needs Accessibility.
    func sendPasteKeystroke() {
        guard Accessibility.isTrusted else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
