import SwiftUI

/// Full-size preview of one clip, over the list.
struct FullPreviewView: View {
    @ObservedObject var model: ShelfViewModel
    let clip: Clip

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: clip.kind.symbolName).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(clip.kind.displayName).font(.headline)
                    Text(clip.metaSummary + " · " + RelativeTime.short(clip.createdAt)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.showFullPreview = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.primary.opacity(0.05))
            Divider().opacity(0.4)
            ScrollView {
                ClipContentView(clip: clip, store: model.store, compact: false)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().opacity(0.4)
            HStack {
                HintRow(hints: [
                    (model.bindings.primaryCombo(for: .paste)?.description ?? "⏎", model.canPasteIntoApp ? "Paste" : "Copy"),
                    (model.bindings.primaryCombo(for: .togglePreview)?.description ?? "␣", "Close"),
                    (model.bindings.primaryCombo(for: .moveUp)?.description ?? "↑", "Prev"),
                    (model.bindings.primaryCombo(for: .moveDown)?.description ?? "↓", "Next"),
                ])
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(VisualEffectBackground(material: .sidebar))
    }
}
