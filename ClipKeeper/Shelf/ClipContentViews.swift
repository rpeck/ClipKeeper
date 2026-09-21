import MarkdownUI
import SwiftUI

/// Renders a clip's content by kind. `compact` limits height for list rows.
struct ClipContentView: View {
    let clip: Clip
    let store: ClipStore
    let compact: Bool

    var body: some View {
        switch clip.kind {
        case .text: textView
        case .markdown: markdownView
        case .code: CodeBlockView(code: clip.text, language: clip.language, maxLines: compact ? 14 : nil, selectable: !compact)
        case .richText: richTextView
        case .image: imageView
        case .link: LinkCardView(clip: clip, store: store, compact: compact)
        case .color: ColorCardView(clip: clip, compact: compact)
        case .files: FilesCardView(clip: clip, compact: compact)
        }
    }

    private var textView: some View {
        Text(compact ? String(clip.text.prefix(1500)) : clip.text)
            .font(.system(size: 13))
            .lineLimit(compact ? 10 : nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SelectableText(enabled: !compact))
    }

    private var markdownView: some View {
        let source = compact ? String(clip.text.prefix(2500)) : clip.text
        return Markdown(source)
            .markdownTheme(.clipKeeper)
            .markdownCodeSyntaxHighlighter(HighlightrSyntaxHighlighter())
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CompactClip(enabled: compact, maxHeight: 260))
    }

    @ViewBuilder
    private var richTextView: some View {
        if let attributed = RenderCache.shared.richText(for: clip, store: store) {
            if compact {
                Text(AttributedString(attributed))
                    .lineLimit(12)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(CompactClip(enabled: true, maxHeight: 240))
            } else {
                RichTextView(attributed: attributed)
                    .frame(minHeight: 200)
            }
        } else {
            Text(compact ? String(clip.text.prefix(1500)) : clip.text)
                .font(.system(size: 13))
                .lineLimit(compact ? 10 : nil)
        }
    }

    @ViewBuilder
    private var imageView: some View {
        let image = compact ? RenderCache.shared.thumbnail(for: clip, store: store) : RenderCache.shared.fullImage(for: clip, store: store)
        if let image {
            Image(nsImage: image)
                .resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: compact ? 260 : .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                .background(CheckerboardBackground().clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
        } else {
            Label("Image unavailable", systemImage: "photo").foregroundStyle(.secondary)
        }
    }
}

/// Text selection only in the full preview. In the list a click must select
/// the card, and selectable text would swallow it.
struct SelectableText: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.textSelection(.enabled)
        } else {
            content.textSelection(.disabled)
        }
    }
}

/// Clips tall content and fades the bottom edge to show it continues.
struct CompactClip: ViewModifier {
    let enabled: Bool
    let maxHeight: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content
                .frame(maxHeight: maxHeight, alignment: .top)
                .clipped()
                .mask(
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 24)
                    }
                )
        } else {
            content
        }
    }
}

/// A syntax-highlighted code block.
struct CodeBlockView: View {
    let code: String
    let language: String?
    let maxLines: Int?
    var selectable: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            CodeHighlighter.shared.highlightedText(code, language: language, maxLines: maxLines)
                .font(.system(size: 12, design: .monospaced))
                .lineSpacing(2)
                .fixedSize(horizontal: true, vertical: true)
                .padding(10)
                .modifier(SelectableText(enabled: selectable))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct LinkCardView: View {
    let clip: Clip
    let store: ClipStore
    let compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let host = clip.linkHost, let icon = store.blobs.favicon(forHost: host) {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "globe").font(.system(size: 18)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                if let title = clip.linkTitle, !title.isEmpty {
                    Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(compact ? 2 : nil)
                }
                Text(clip.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : nil)
                    .truncationMode(.middle)
                    .modifier(SelectableText(enabled: !compact))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ColorCardView: View {
    let clip: Clip
    let compact: Bool

    var body: some View {
        let parsed = clip.colorHex.flatMap { ColorParser.parse($0) }
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(parsed.map { Color(nsColor: $0.nsColor) } ?? .gray)
                .frame(width: compact ? 52 : 120, height: compact ? 52 : 120)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                .background(CheckerboardBackground().clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
            VStack(alignment: .leading, spacing: 3) {
                Text(parsed?.hex ?? clip.title).font(.system(size: 16, weight: .semibold, design: .monospaced))
                if let parsed {
                    Text(parsed.rgbString).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    if !compact {
                        Text(parsed.swiftString).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                if clip.text != (parsed?.hex ?? ""), clip.text.count < 60 {
                    Text(clip.text).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FilesCardView: View {
    let clip: Clip
    let compact: Bool

    var body: some View {
        let paths = clip.filePaths
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array((compact ? Array(paths.prefix(4)) : paths).enumerated()), id: \.offset) { _, path in
                HStack(spacing: 8) {
                    Image(nsImage: AppIcons.icon(forFilePath: path)).resizable().frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text((path as NSString).lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text((path as NSString).deletingLastPathComponent).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            if compact, paths.count > 4 {
                Text("and \(paths.count - 4) more").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Light checkerboard behind transparent images and colors.
struct CheckerboardBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 8
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = 0
                while x < size.width {
                    if (row + col) % 2 == 0 {
                        ctx.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(Color.primary.opacity(0.06)))
                    }
                    x += cell; col += 1
                }
                y += cell; row += 1
            }
        }
    }
}
