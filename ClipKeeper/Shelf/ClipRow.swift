import SwiftUI

/// One clip card in the shelf list.
struct ClipRow: View {
    @ObservedObject var model: ShelfViewModel
    let clip: Clip
    let index: Int
    let isSelected: Bool
    let isChecked: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if model.selectMode || hovering || isChecked {
                    Button { model.toggleChecked(clip) } label: {
                        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)
                    .transition(.opacity)
                }
                ClipContentView(clip: clip, store: model.store, compact: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.07), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.select(index: index); model.perform(.paste) }
        .onTapGesture(count: 1) { model.select(index: index) }
        .contextMenu { ClipContextMenu(model: model, clip: clip, index: index) }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let icon = AppIcons.icon(forBundleID: clip.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
            } else {
                Image(systemName: clip.kind.symbolName).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 14)
            }
            Text(clip.metaSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if clip.pinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.orange)
            }
            Text(RelativeTime.short(clip.createdAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
    }
}

/// Right-click menu for a clip. It mirrors the keyboard actions.
struct ClipContextMenu: View {
    @ObservedObject var model: ShelfViewModel
    let clip: Clip
    let index: Int

    private func hint(_ action: KeyAction) -> String {
        model.bindings.primaryCombo(for: action).map { "  \($0.description)" } ?? ""
    }

    var body: some View {
        let pasteWord = model.canPasteIntoApp ? "Paste" : "Copy"
        Button("\(pasteWord)\(hint(.paste))") { model.select(index: index); model.perform(.paste) }
        Button("\(pasteWord) as Plain Text\(hint(.pastePlain))") { model.select(index: index); model.perform(.pastePlain) }
        Menu("\(pasteWord) as…") {
            let variants = PasteVariant.variants(for: clip, snapshot: model.store.snapshot(for: clip))
            ForEach(variants) { v in
                Button(v.title) { model.requestPaste(clip, v) }
            }
        }
        Button("Copy to Clipboard Only\(hint(.copyOnly))") { model.select(index: index); model.perform(.copyOnly) }
        Divider()
        Button(clip.kind == .image ? "Crop…\(hint(.edit))" : "Edit…\(hint(.edit))") { model.select(index: index); model.perform(.edit) }
            .disabled(clip.kind == .files)
        Button("Save As…\(hint(.saveAs))") { model.select(index: index); model.perform(.saveAs) }
        Button(clip.pinned ? "Unpin\(hint(.pin))" : "Pin\(hint(.pin))") { model.select(index: index); model.perform(.pin) }
        Button("Move to Collection…\(hint(.moveToCollection))") { model.select(index: index); model.perform(.moveToCollection) }
        Button("Duplicate\(hint(.duplicate))") { model.select(index: index); model.perform(.duplicate) }
        Button("Full Preview\(hint(.togglePreview))") { model.select(index: index); model.perform(.togglePreview) }
        Divider()
        Button("Delete…\(hint(.delete))") { model.select(index: index); model.perform(.delete) }
    }
}
