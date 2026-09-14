import SwiftUI

/// Footer that shows the keys for the most useful actions on the selected clip.
struct KeyHintBar: View {
    @ObservedObject var model: ShelfViewModel

    private func combo(_ action: KeyAction) -> String {
        model.bindings.primaryCombo(for: action)?.description ?? "?"
    }

    var body: some View {
        let clip = model.selectedClip
        let pasteWord = model.canPasteIntoApp ? "Paste" : "Copy"
        var hints: [(String, String)] = []
        if clip != nil {
            hints.append((combo(.paste), pasteWord))
            if let clip, clip.kind != .image, clip.kind != .text || clip.hasRich { hints.append((combo(.pastePlain), "Plain")) }
            if model.canPasteIntoApp { hints.append((combo(.copyOnly), "Copy only")) }
            hints.append((combo(.pasteAs), "\(pasteWord) as…"))
            if let clip, clip.kind == .image { hints.append((combo(.edit), "Crop")) }
            else if let clip, clip.kind != .files { hints.append((combo(.edit), "Edit")) }
            hints.append((combo(.saveAs), "Save as…"))
            hints.append((combo(.togglePreview), "Preview"))
            hints.append((combo(.moveToCollection), "Move"))
            hints.append((combo(.delete), "Delete"))
        } else {
            hints.append((combo(.nextSet), "Next set"))
            hints.append((combo(.newCollection), "New collection"))
            hints.append((combo(.close), "Close"))
        }
        return FlowLayout(spacing: 10, rowSpacing: 4) {
            ForEach(Array(hints.enumerated()), id: \.offset) { _, h in
                HStack(spacing: 4) {
                    Text(h.0)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
                    Text(h.1).font(.caption).foregroundStyle(.secondary)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
    }
}
