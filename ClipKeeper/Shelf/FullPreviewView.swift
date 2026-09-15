import SwiftUI

/// Full-size preview of one clip, over the list: a header card with the
/// details, the content in its own card, and the actions as buttons.
struct FullPreviewView: View {
    @ObservedObject var model: ShelfViewModel
    let clip: Clip

    private func combo(_ action: KeyAction) -> String {
        model.bindings.primaryCombo(for: action)?.description ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(12)
            ScrollView {
                ClipContentView(clip: clip, store: model.store, compact: false)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            Divider().opacity(0.4)
            actions
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(VisualEffectBackground(material: .sidebar))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: clip.kind.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.kind.displayName).font(.headline)
                    Text(clip.kind == .image || clip.title.isEmpty ? clip.metaSummary : clip.title)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button { model.showFullPreview = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Close (\(combo(.togglePreview)))")
            }
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    private var chips: [String] {
        var list: [String] = []
        if let formats = clip.formats, !formats.isEmpty { list.append(formats) }
        switch clip.kind {
        case .image:
            if let w = clip.imageWidth, let h = clip.imageHeight { list.append("\(w) × \(h) px") }
        case .link:
            if let host = clip.linkHost { list.append(host) }
        case .files:
            list.append(clip.filePaths.count == 1 ? "1 file" : "\(clip.filePaths.count) files")
        case .color:
            if let hex = clip.colorHex { list.append(hex) }
        default:
            list.append(clip.lineCount == 1 ? "1 line" : "\(clip.lineCount) lines")
            list.append(clip.charCount == 1 ? "1 character" : "\(clip.charCount) characters")
            if clip.kind == .code, let language = clip.language { list.append(CodeLanguage.named(language)?.displayName ?? language) }
        }
        list.append(ByteCountFormatter.string(fromByteCount: Int64(clip.byteCount), countStyle: .file))
        if let app = clip.sourceAppName { list.append("From \(app)") }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        list.append(f.string(from: clip.createdAt))
        if clip.pinned { list.append("Pinned") }
        return list
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6, rowSpacing: 6) {
                Button {
                    model.perform(.paste)
                } label: {
                    Label(model.canPasteIntoApp ? "Paste" : "Copy", systemImage: "arrow.down.doc").fixedSize()
                }
                .buttonStyle(.borderedProminent)
                .help("\(model.canPasteIntoApp ? "Paste" : "Copy") (\(combo(.paste)))")
                Button { model.perform(.copyOnly) } label: { Label("Copy", systemImage: "doc.on.doc").fixedSize() }
                    .help("Copy to the clipboard only (\(combo(.copyOnly)))")
                Button { model.perform(.saveAs) } label: { Label("Save as…", systemImage: "square.and.arrow.down").fixedSize() }
                    .help("Save as… (\(combo(.saveAs)))")
                if clip.kind != .files {
                    Button { model.perform(.edit) } label: { Label(clip.kind == .image ? "Crop" : "Edit", systemImage: clip.kind == .image ? "crop" : "pencil").fixedSize() }
                        .help("\(clip.kind == .image ? "Crop" : "Edit") (\(combo(.edit)))")
                }
            }
            HintRow(hints: [(combo(.moveUp), "Previous clip"), (combo(.moveDown), "Next clip"), (combo(.togglePreview), "Close")])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlSize(.small)
    }
}
