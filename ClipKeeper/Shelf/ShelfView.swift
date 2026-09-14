import SwiftUI

/// The root view of the shelf.
struct ShelfView: View {
    @ObservedObject var model: ShelfViewModel
    @ObservedObject var prefs = Preferences.shared
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                searchBar
                SetTabsView(model: model)
                Divider().opacity(0.4)
                clipList
                Divider().opacity(0.4)
                KeyHintBar(model: model)
            }
            .allowsHitTesting(model.overlay == nil)

            if model.showFullPreview, let clip = model.selectedClip {
                FullPreviewView(model: model, clip: clip)
                    .transition(.opacity)
            }

            if let overlay = model.overlay {
                OverlayHost(model: model, overlay: overlay)
                    .transition(.opacity)
            }

            if let toast = model.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(radius: 6, y: 2)
                        .padding(.bottom, 52)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.toast)
        .animation(.easeOut(duration: 0.12), value: model.showFullPreview)
        .background(VisualEffectBackground(material: .sidebar))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .onChange(of: model.searchFocused) { _, focused in
            if focused && model.overlay == nil { searchFocused = true }
        }
        .onChange(of: model.overlay?.id) { _, id in
            if id == nil { DispatchQueue.main.async { searchFocused = true } }
        }
        .onAppear { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if prefs.isPaused {
                Label("Paused", systemImage: "pause.fill")
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
                    .help("Capture is paused")
            }
            Button { model.requestOpenSettings() } label: {
                Image(systemName: "gearshape").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05))
    }

    private var clipList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if model.clips.isEmpty {
                        emptyState
                    }
                    ForEach(Array(model.clips.enumerated()), id: \.element.uuid) { index, clip in
                        ClipRow(model: model, clip: clip, index: index, isSelected: index == model.selectedIndex, isChecked: model.selectedUUIDs.contains(clip.uuid))
                            .id(clip.uuid)
                    }
                }
                .padding(10)
            }
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(target, anchor: nil) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? (model.currentSet.id == "history" ? "Nothing copied yet" : "This collection is empty") : "No matches")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(model.query.isEmpty ? (model.currentSet.id == "history" ? "Copy something and it shows up here." : "Select a clip and press \(model.bindings.primaryCombo(for: .moveToCollection)?.description ?? "⌘M") to move it here.") : "Try a different search.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

/// The row of set tabs: History plus each collection.
struct SetTabsView: View {
    @ObservedObject var model: ShelfViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(model.sets.enumerated()), id: \.element.id) { index, set in
                        let selected = index == model.currentSetIndex
                        Button { model.selectSet(index: index) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: index == 0 ? "clock" : "folder")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(set.name)
                                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05), in: Capsule())
                            .foregroundStyle(selected ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .id(set.id)
                        .contextMenu {
                            if index > 0 {
                                Button("Rename…") { model.selectSet(index: index); model.renameCurrentCollection() }
                                Button("Delete Collection…") { model.selectSet(index: index); model.deleteCurrentCollection() }
                            }
                        }
                    }
                    Button { model.perform(.newCollection) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(6)
                            .background(Color.primary.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("New collection (\(model.bindings.primaryCombo(for: .newCollection)?.description ?? "⌘N"))")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: model.currentSetIndex) { _, idx in
                if model.sets.indices.contains(idx) { withAnimation { proxy.scrollTo(model.sets[idx].id) } }
            }
        }
    }
}
