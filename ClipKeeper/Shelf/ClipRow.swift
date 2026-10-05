import SwiftUI

/// One clip card in the shelf list.
struct ClipRow: View {
    @ObservedObject var model: ShelfViewModel
    let clip: Clip
    let index: Int
    let isSelected: Bool
    let isChecked: Bool
    @State private var hovering = false
    @State private var showInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                // The checkbox column is always reserved so the content never
                // re-wraps when it appears. It is faint until hover or select mode.
                Button { model.toggleChecked(clip) } label: {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15))
                        .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
                .opacity(hovering || isChecked || !model.selectedUUIDs.isEmpty ? 1 : 0.22)
                .help(isChecked ? "Uncheck (⌘⇧A)" : "Check this clip for a bulk action (⌘⇧A)")
                ClipContentView(clip: clip, store: model.store, compact: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
            }
            footer
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? Color.accentColor.opacity(0.08) : .clear))
                .shadow(color: .black.opacity(0.07), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.1), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.select(index: index); model.perform(.paste) }
        .onTapGesture(count: 1) { model.select(index: index) }
        .onDrag { ClipDrag.itemProvider(for: clip, store: model.store) }
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
            Button { showInfo.toggle() } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(clip.detailsTooltip)
            .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                Text(clip.detailsTooltip)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(minWidth: 200, maxWidth: 360, alignment: .leading)
            }
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
            Button {
                model.select(index: index)
                model.perform(.delete)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(trashHovering ? Color.red : Color.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { trashHovering = $0 }
            .help("Delete this clip")
        }
    }
    @State private var trashHovering = false
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
        Button("Share…\(hint(.share))") { model.select(index: index); model.perform(.share) }
        Button("Send with AirDrop\(hint(.airDrop))") { model.select(index: index); model.perform(.airDrop) }
        Button(clip.pinned ? "Unpin\(hint(.pin))" : "Pin\(hint(.pin))") { model.select(index: index); model.perform(.pin) }
        Button("Move to Collection…\(hint(.moveToCollection))") { model.select(index: index); model.perform(.moveToCollection) }
        Button("Duplicate\(hint(.duplicate))") { model.select(index: index); model.perform(.duplicate) }
        Button("Full Preview\(hint(.togglePreview))") { model.select(index: index); model.perform(.togglePreview) }
        if clip.kind == .files {
            Divider()
            Button("Import File Contents as Clips\(hint(.importContents))") { model.select(index: index); model.perform(.importContents) }
            Button("Reveal in Finder\(hint(.openLink))") { model.select(index: index); model.perform(.openLink) }
        }
        Divider()
        Button("Import Files…\(hint(.importFiles))") { model.perform(.importFiles) }
        Divider()
        Button("Delete…\(hint(.delete))") { model.select(index: index); model.perform(.delete) }
    }
}
