import AppKit
import Foundation
import SwiftUI

/// An item in a keyboard-driven picker overlay.
struct PickerItem: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String? = nil
    var symbol: String? = nil
}

/// State for the shelf. All keyboard actions resolve here.
@MainActor
final class ShelfViewModel: ObservableObject {
    enum Overlay: Identifiable {
        case picker(title: String, items: [PickerItem], onChoose: (PickerItem) -> Void)
        case prompt(title: String, placeholder: String, initial: String, onCommit: (String) -> Void)
        case confirm(title: String, message: String, confirmTitle: String, onConfirm: () -> Void)

        var id: String {
            switch self {
            case .picker(let t, _, _): return "picker-\(t)"
            case .prompt(let t, _, _, _): return "prompt-\(t)"
            case .confirm(let t, _, _, _): return "confirm-\(t)"
            }
        }
    }

    let store: ClipStore
    let bindings: KeyBindingStore
    let prefs: Preferences

    @Published var query: String = "" {
        didSet { if query != oldValue { reload(keepSelection: false) } }
    }
    @Published private(set) var currentSetIndex: Int = 0
    @Published private(set) var clips: [Clip] = []
    @Published var selectedIndex: Int = 0
    @Published var selectedUUIDs: Set<String> = []
    @Published var selectMode: Bool = false
    @Published var showFullPreview: Bool = false
    @Published var overlay: Overlay? = nil
    @Published var overlaySelection: Int = 0
    @Published var promptText: String = ""
    @Published var toast: String? = nil
    @Published var scrollTarget: String? = nil
    @Published var searchFocused: Bool = true

    var requestClose: () -> Void = {}
    var requestPaste: (Clip, PasteVariant) -> Void = { _, _ in }
    var requestCopyOnly: (Clip, PasteVariant) -> Void = { _, _ in }
    var requestEdit: (Clip) -> Void = { _ in }
    var requestSaveAs: ([Clip]) -> Void = { _ in }
    var requestOpenSettings: () -> Void = {}

    private var toastTask: Task<Void, Never>?
    private var storeObservation: Any?

    init(store: ClipStore, bindings: KeyBindingStore, prefs: Preferences = .shared) {
        self.store = store
        self.bindings = bindings
        self.prefs = prefs
        storeObservation = store.$changeToken
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isActive { self.reload(keepSelection: true) } else { self.needsReload = true }
            }
        reload(keepSelection: false)
    }

    /// True while the shelf is on screen. A hidden shelf does not reload or
    /// render, so captures never wait on the interface.
    var isActive = false
    private var needsReload = false

    // MARK: Derived state

    var sets: [ClipSet] { store.sets }

    var currentSet: ClipSet {
        let s = sets
        guard !s.isEmpty else { return .history }
        return s[min(currentSetIndex, s.count - 1)]
    }

    var selectedClip: Clip? {
        guard !clips.isEmpty else { return nil }
        return clips[max(0, min(selectedIndex, clips.count - 1))]
    }

    /// Clips an action applies to: the checked clips in select mode, else the selected clip.
    var actionTargets: [Clip] {
        if selectMode, !selectedUUIDs.isEmpty {
            return clips.filter { selectedUUIDs.contains($0.uuid) }
        }
        return selectedClip.map { [$0] } ?? []
    }

    var canPasteIntoApp: Bool { prefs.pasteIntoApp && Accessibility.isTrusted }

    // MARK: Lifecycle

    func prepareForShow() {
        isActive = true
        needsReload = false
        overlay = nil
        showFullPreview = false
        selectMode = false
        selectedUUIDs = []
        toast = nil
        if !query.isEmpty { query = "" } else { reload(keepSelection: false) }
        selectedIndex = 0
        searchFocused = true
        scrollTarget = clips.first?.uuid
    }

    func reload(keepSelection: Bool) {
        let previous = keepSelection ? selectedClip?.uuid : nil
        if currentSetIndex >= sets.count { currentSetIndex = max(0, sets.count - 1) }
        clips = store.clips(in: currentSet, query: query)
        if let previous, let idx = clips.firstIndex(where: { $0.uuid == previous }) {
            selectedIndex = idx
        } else {
            selectedIndex = min(selectedIndex, max(0, clips.count - 1))
            if !keepSelection { selectedIndex = 0 }
        }
        let present = Set(clips.map(\.uuid))
        selectedUUIDs = selectedUUIDs.intersection(present)
    }

    func selectSet(index: Int) {
        guard index >= 0, index < sets.count, index != currentSetIndex else { return }
        currentSetIndex = index
        selectedUUIDs = []
        reload(keepSelection: false)
        scrollTarget = clips.first?.uuid
    }

    func select(index: Int) {
        guard !clips.isEmpty else { return }
        selectedIndex = max(0, min(index, clips.count - 1))
        scrollTarget = clips[selectedIndex].uuid
    }

    func toggleChecked(_ clip: Clip) {
        if selectedUUIDs.contains(clip.uuid) { selectedUUIDs.remove(clip.uuid) } else { selectedUUIDs.insert(clip.uuid) }
        if !selectedUUIDs.isEmpty { selectMode = true }
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    // MARK: Key handling

    /// Returns true when the event was consumed.
    func handle(event: NSEvent) -> Bool {
        guard let combo = KeyCombo(event: event) else { return false }
        if let overlay { return handleOverlay(overlay, combo: combo) }
        if showFullPreview {
            if let action = bindings.resolve(event: event, searchHasText: false) {
                switch action {
                case .close, .togglePreview: showFullPreview = false; return true
                case .moveUp, .moveDown, .paste, .pastePlain, .copyOnly, .pasteAs, .saveAs, .edit, .pin: return perform(action)
                default: return true
                }
            }
            return true
        }
        guard let action = bindings.resolve(event: event, searchHasText: !query.isEmpty) else { return false }
        return perform(action)
    }

    private func handleOverlay(_ overlay: Overlay, combo: KeyCombo) -> Bool {
        switch overlay {
        case .picker(_, let items, let onChoose):
            if let action = bindings.action(for: combo) {
                switch action {
                case .moveUp: overlaySelection = max(0, overlaySelection - 1); return true
                case .moveDown: overlaySelection = min(items.count - 1, overlaySelection + 1); return true
                case .close: self.overlay = nil; return true
                case .paste:
                    if items.indices.contains(overlaySelection) { let item = items[overlaySelection]; self.overlay = nil; onChoose(item) }
                    return true
                default: break
                }
            }
            if combo.key == "escape" { self.overlay = nil; return true }
            if combo.isEnter, combo.modifiers.isEmpty { if items.indices.contains(overlaySelection) { let item = items[overlaySelection]; self.overlay = nil; onChoose(item) }; return true }
            if combo.modifiers.isEmpty, let n = Int(combo.key), n >= 1, n <= items.count { let item = items[n - 1]; self.overlay = nil; onChoose(item); return true }
            return true
        case .prompt(_, _, _, let onCommit):
            if combo.key == "escape" { self.overlay = nil; return true }
            if combo.isEnter, combo.modifiers.isEmpty {
                let text = promptText
                self.overlay = nil
                onCommit(text)
                return true
            }
            return false // let the text field edit
        case .confirm(_, _, _, let onConfirm):
            if combo.key == "escape" || combo.key == "n" { self.overlay = nil; return true }
            if combo.isEnter || combo.key == "y" || combo.key == "delete" { self.overlay = nil; onConfirm(); return true }
            return true
        }
    }

    // MARK: Actions

    @discardableResult
    func perform(_ action: KeyAction) -> Bool {
        switch action {
        case .moveUp: select(index: selectedIndex - 1); return true
        case .moveDown: select(index: selectedIndex + 1); return true
        case .previousSet: selectSet(index: (currentSetIndex - 1 + sets.count) % max(1, sets.count)); return true
        case .nextSet: selectSet(index: (currentSetIndex + 1) % max(1, sets.count)); return true
        case .close:
            if showFullPreview { showFullPreview = false } else { requestClose() }
            return true
        case .togglePreview:
            if selectedClip != nil { showFullPreview.toggle() }
            return true
        case .paste:
            guard let clip = selectedClip else { return true }
            requestPaste(clip, .original)
            return true
        case .pastePlain:
            guard let clip = selectedClip else { return true }
            requestPaste(clip, plainVariant(for: clip))
            return true
        case .copyOnly:
            guard let clip = selectedClip else { return true }
            requestCopyOnly(clip, .original)
            return true
        case .pasteAs:
            guard let clip = selectedClip else { return true }
            showPasteAsPicker(for: clip)
            return true
        case .slot1, .slot2, .slot3, .slot4, .slot5, .slot6, .slot7, .slot8, .slot9:
            if let n = action.slotNumber, clips.indices.contains(n - 1) { requestPaste(clips[n - 1], .original) }
            return true
        case .edit:
            guard let clip = selectedClip else { return true }
            requestEdit(clip)
            return true
        case .saveAs:
            let targets = actionTargets
            if !targets.isEmpty { requestSaveAs(targets) }
            return true
        case .pin:
            guard let clip = selectedClip else { return true }
            store.togglePin(clip)
            showToast(clip.pinned ? "Unpinned" : "Pinned")
            return true
        case .duplicate:
            guard let clip = selectedClip else { return true }
            if let dup = store.duplicate(clip) { showToast("Duplicated"); scrollTarget = dup.uuid; select(index: clips.firstIndex(of: dup) ?? 0) }
            return true
        case .moveToCollection:
            let targets = actionTargets
            if !targets.isEmpty { showMovePicker(for: targets) }
            return true
        case .delete:
            let targets = actionTargets
            guard !targets.isEmpty else { return true }
            if prefs.confirmDelete {
                let title = targets.count == 1 ? "Delete this clip?" : "Delete \(targets.count) clips?"
                overlay = .confirm(title: title, message: "This cannot be undone.", confirmTitle: "Delete") { [weak self] in
                    self?.deleteNow(targets)
                }
            } else {
                deleteNow(targets)
            }
            return true
        case .toggleSelectMode:
            selectMode.toggle()
            if !selectMode { selectedUUIDs = [] } else if let c = selectedClip { selectedUUIDs.insert(c.uuid) }
            return true
        case .selectAll:
            selectMode = true
            selectedUUIDs = Set(clips.map(\.uuid))
            return true
        case .extendSelectionUp, .extendSelectionDown:
            guard !clips.isEmpty else { return true }
            selectMode = true
            selectedUUIDs.insert(clips[selectedIndex].uuid)
            let next = action == .extendSelectionUp ? selectedIndex - 1 : selectedIndex + 1
            select(index: next)
            selectedUUIDs.insert(clips[selectedIndex].uuid)
            return true
        case .newCollection:
            promptText = ""
            overlay = .prompt(title: "New Collection", placeholder: "Name", initial: "") { [weak self] name in
                guard let self, let c = self.store.createCollection(named: name) else { return }
                if let idx = self.sets.firstIndex(where: { $0.id == c.uuid }) { self.selectSet(index: idx) }
                self.showToast("Created \(c.name)")
            }
            return true
        }
    }

    private func deleteNow(_ targets: [Clip]) {
        let idx = selectedIndex
        store.delete(targets)
        selectedUUIDs = []
        if selectMode, clips.isEmpty { selectMode = false }
        select(index: idx)
        showToast(targets.count == 1 ? "Deleted" : "Deleted \(targets.count) clips")
    }

    private func plainVariant(for clip: Clip) -> PasteVariant {
        switch clip.kind {
        case .link: return .url
        case .color: return .colorHex
        case .files: return .filePaths
        case .image: return .original
        default: return .plainText
        }
    }

    func showPasteAsPicker(for clip: Clip) {
        let snapshot = store.snapshot(for: clip)
        let variants = PasteVariant.variants(for: clip, snapshot: snapshot)
        let items = variants.map { PickerItem(id: $0.id, title: $0.title) }
        overlaySelection = 0
        overlay = .picker(title: canPasteIntoApp ? "Paste as…" : "Copy as…", items: items) { [weak self] item in
            guard let variant = variants.first(where: { $0.id == item.id }) else { return }
            self?.requestPaste(clip, variant)
        }
    }

    func showMovePicker(for targets: [Clip]) {
        var items: [PickerItem] = []
        for (i, set) in sets.enumerated() where set.id != currentSet.id {
            items.append(PickerItem(id: set.id, title: set.name, symbol: i == 0 ? "clock" : "folder"))
        }
        items.append(PickerItem(id: "__new__", title: "New Collection…", symbol: "plus"))
        overlaySelection = 0
        let count = targets.count
        overlay = .picker(title: count == 1 ? "Move to…" : "Move \(count) clips to…", items: items) { [weak self] item in
            guard let self else { return }
            if item.id == "__new__" {
                self.promptText = ""
                self.overlay = .prompt(title: "New Collection", placeholder: "Name", initial: "") { [weak self] name in
                    guard let self, let c = self.store.createCollection(named: name) else { return }
                    self.store.move(targets, to: .collection(c))
                    self.selectedUUIDs = []
                    self.showToast("Moved to \(c.name)")
                }
                return
            }
            guard let set = self.sets.first(where: { $0.id == item.id }) else { return }
            self.store.move(targets, to: set)
            self.selectedUUIDs = []
            if self.selectMode { self.selectMode = false }
            self.showToast("Moved to \(set.name)")
        }
    }

    func renameCurrentCollection() {
        guard case .collection(let c) = currentSet else { return }
        promptText = c.name
        overlay = .prompt(title: "Rename Collection", placeholder: "Name", initial: c.name) { [weak self] name in
            self?.store.renameCollection(c, to: name)
        }
    }

    func deleteCurrentCollection() {
        guard case .collection(let c) = currentSet else { return }
        overlay = .confirm(title: "Delete “\(c.name)”?", message: "Its clips move back to History.", confirmTitle: "Delete") { [weak self] in
            guard let self else { return }
            self.store.deleteCollection(c)
            self.selectSet(index: 0)
        }
    }
}
