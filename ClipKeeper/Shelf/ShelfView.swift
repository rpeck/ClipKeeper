import SwiftUI
import UniformTypeIdentifiers

/// The root view of the shelf.
struct ShelfView: View {
    @ObservedObject var model: ShelfViewModel
    @ObservedObject var prefs = Preferences.shared
    @FocusState private var searchFocused: Bool
    @State private var fileDropTargeted = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                searchBar
                SetTabsView(model: model)
                if !model.query.isEmpty {
                    HStack(spacing: 8) {
                        Text(model.clips.count == 1 ? "1 match" : "\(model.clips.count) matches")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Picker("Sort", selection: $model.searchNewestFirst) {
                            Text("Best match").tag(false)
                            Text("Newest").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .labelsHidden()
                        .frame(width: 150)
                        .help("Order the search results by match quality or by time")
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
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

            // Drag the left edge to change the width.
            HStack(spacing: 0) {
                ResizeHandle(model: model)
                Spacer()
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
                Button { prefs.isPaused = false } label: {
                    Label("Paused", systemImage: "pause.fill")
                        .font(.caption2.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Capture is paused. Click to resume.")
            }
            Button { model.perform(.keepShelfOpen) } label: {
                Image(systemName: model.pinned ? "pin.fill" : "pin")
                    .foregroundStyle(model.pinned ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(model.pinned ? "Pinned: the shelf stays open after a paste and when you click elsewhere. Click to unpin (\(model.bindings.primaryCombo(for: .keepShelfOpen)?.description ?? "⌘⇧P"))." : "Keep the shelf open for drag and drop (\(model.bindings.primaryCombo(for: .keepShelfOpen)?.description ?? "⌘⇧P"))")
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
            // Files dropped anywhere on the list become clips in the current set.
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $fileDropTargeted) { providers in
                guard ClipDrag.hasFiles(providers) else { return false }
                let set = model.currentSet
                ClipDrag.fileURLs(from: providers) { urls in model.dropFiles(urls, onto: set) }
                return true
            }
            .overlay { FileDropHighlight(active: fileDropTargeted) }
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

/// A thin strip on the left edge. Drag it to change the shelf width.
struct ResizeHandle: View {
    @ObservedObject var model: ShelfViewModel
    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(hovering || dragging ? 0.35 : 0))
            .frame(width: 5)
            .frame(maxHeight: .infinity)
            .overlay {
                // A grip in the middle of the edge shows that it can be dragged.
                Capsule()
                    .fill(hovering || dragging ? Color.accentColor : Color.primary.opacity(0.28))
                    .frame(width: 3, height: 36)
            }
            .contentShape(Rectangle().inset(by: -3))
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else if !dragging { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in
                        dragging = true
                        model.requestResize(NSEvent.mouseLocation.x)
                    }
                    .onEnded { _ in
                        dragging = false
                        model.requestResizeEnd()
                        if !hovering { NSCursor.pop() }
                    }
            )
            .help("Drag to change the width")
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The row of set tabs: History plus each collection.
struct SetTabsView: View {
    @ObservedObject var model: ShelfViewModel
    @State private var dropTarget: String?

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
                        .overlay(
                            Capsule().strokeBorder(Color.accentColor, lineWidth: 2)
                                .opacity(dropTarget == set.id ? 1 : 0)
                        )
                        .onDrop(of: [ClipDrag.typeIdentifier, UTType.fileURL.identifier], isTargeted: Binding(
                            get: { dropTarget == set.id },
                            set: { dropTarget = $0 ? set.id : (dropTarget == set.id ? nil : dropTarget) }
                        )) { providers in
                            if ClipDrag.hasFiles(providers) {
                                ClipDrag.fileURLs(from: providers) { urls in model.dropFiles(urls, onto: set) }
                            } else {
                                ClipDrag.uuid(from: providers) { uuid in
                                    if let uuid { model.dropClip(uuid: uuid, onto: set) }
                                }
                            }
                            return true
                        }
                        .contextMenu {
                            if index > 0 {
                                Button("Rename…") { model.selectSet(index: index); model.renameCurrentCollection() }
                                Button("Delete Collection…") { model.selectSet(index: index); model.deleteCurrentCollection() }
                            } else {
                                Text("History fills on every copy. Drag a clip onto a collection tab to move it.")
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

/// The dashed frame and label shown while files are dragged over the list.
struct FileDropHighlight: View {
    let active: Bool

    var body: some View {
        if active {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(6)
                .overlay {
                    Text("Drop to import each file as a clip")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
                .allowsHitTesting(false)
        }
    }
}
