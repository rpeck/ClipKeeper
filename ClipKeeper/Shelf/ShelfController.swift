import AppKit
import SwiftUI

/// Shows and hides the shelf, routes key events, and runs the actions that
/// leave the shelf: paste, edit, and save.
@MainActor
final class ShelfController {
    let viewModel: ShelfViewModel
    private let store: ClipStore
    private let prefs: Preferences
    private let panel: ShelfPanel
    private let hosting: NSHostingView<ShelfView>
    private var keyMonitor: Any?
    private var resignObserver: Any?
    private(set) var isVisible = false
    private var isAnimating = false

    var openSettings: () -> Void = {}

    /// The shelf's root view, for debug snapshots.
    var snapshotView: NSView { hosting }

    private let margin: CGFloat = 10
    private let animationDuration: TimeInterval = 0.18

    init(store: ClipStore, bindings: KeyBindingStore, prefs: Preferences = .shared) {
        self.store = store
        self.prefs = prefs
        viewModel = ShelfViewModel(store: store, bindings: bindings, prefs: prefs)
        panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: prefs.shelfWidth, height: 600))
        hosting = NSHostingView(rootView: ShelfView(model: viewModel))
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 14
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting

        viewModel.requestClose = { [weak self] in self?.hide() }
        viewModel.requestPaste = { [weak self] clip, variant in self?.paste(clip, variant: variant, keystroke: true) }
        viewModel.requestCopyOnly = { [weak self] clip, variant in self?.paste(clip, variant: variant, keystroke: false) }
        viewModel.requestEdit = { [weak self] clip in self?.edit(clip) }
        viewModel.requestNewClip = { [weak self] set in self?.newClip(into: set) }
        viewModel.requestSaveAs = { [weak self] clips in self?.saveAs(clips) }
        viewModel.requestOpenSettings = { [weak self] in self?.hide { self?.openSettings() } }
        viewModel.requestImportFiles = { [weak self] set in self?.chooseFilesToImport(into: set) }
        viewModel.requestImport = { [weak self] urls, set in self?.importFiles(urls, into: set) }
        viewModel.requestShare = { [weak self] clips, airDrop in self?.share(clips, airDropOnly: airDrop) }
        viewModel.requestResize = { [weak self] mouseX in self?.resize(toMouseX: mouseX) }
        viewModel.requestResizeEnd = { [weak self] in self?.finishResize() }

        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isVisible, !self.isAnimating else { return }
                // A pinned shelf stays open when another window takes the key.
                if self.viewModel.pinned { return }
                // A popover or other child window of the shelf took the key. Stay open.
                if let key = NSApp.keyWindow, key !== self.panel, key.parent === self.panel || key.className.contains("Popover") { return }
                self.hide()
            }
        }
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    // MARK: Show and hide

    /// True when the edge trigger opened the shelf. Such a shelf closes when the mouse leaves it.
    private(set) var openedByEdge = false

    var panelFrame: NSRect { panel.frame }

    func show(on screen: NSScreen? = nil, byEdge: Bool = false) {
        guard !isVisible else { return }
        isVisible = true
        openedByEdge = byEdge
        viewModel.prepareForShow()
        CodeHighlighter.shared.appearanceChanged()

        let (onscreen, offscreen) = frames(on: screen)
        panel.setFrame(offscreen, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        installKeyMonitor()

        isAnimating = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = animationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(onscreen, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isAnimating = false
                self?.viewModel.searchFocused = true
            }
        })
    }

    func hide(completion: (() -> Void)? = nil) {
        guard isVisible else { completion?(); return }
        isVisible = false
        openedByEdge = false
        viewModel.isActive = false
        removeKeyMonitor()
        let (_, offscreen) = frames(current: panel.frame)
        isAnimating = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = animationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(offscreen, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isAnimating = false
                if !self.isVisible { self.panel.orderOut(nil) }
                completion?()
            }
        })
    }

    // MARK: Resize by dragging the left edge

    /// Sets the width so the left edge follows the mouse. The right edge stays.
    private func resize(toMouseX mouseX: CGFloat) {
        var frame = panel.frame
        let newWidth = max(200, min(800, frame.maxX - mouseX))
        frame.origin.x = frame.maxX - newWidth
        frame.size.width = newWidth
        panel.setFrame(frame, display: true)
    }

    private func finishResize() {
        prefs.shelfWidth = panel.frame.width
    }

    /// The target screen is the one with the focused window, else the mouse.
    private func targetScreen() -> NSScreen {
        if let frame = Accessibility.focusedWindowFrame() {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if let s = NSScreen.screens.first(where: { $0.frame.contains(center) }) { return s }
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func frames(on requested: NSScreen? = nil, current: NSRect? = nil) -> (onscreen: NSRect, offscreen: NSRect) {
        let screen = requested ?? current.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } } ?? targetScreen()
        let visible = screen.visibleFrame
        let width = min(prefs.shelfWidth, visible.width - 2 * margin)
        let height = visible.height - 2 * margin
        let onscreen = NSRect(x: visible.maxX - width - margin, y: visible.minY + margin, width: width, height: height)
        let offscreen = NSRect(x: visible.maxX + 8, y: onscreen.minY, width: width, height: height)
        return (onscreen, offscreen)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.viewModel.handle(event: event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: Actions

    private func paste(_ clip: Clip, variant: PasteVariant, keystroke: Bool) {
        let snapshot = store.snapshot(for: clip)
        guard Paster.shared.copy(clip: clip, variant: variant, original: snapshot) else {
            viewModel.showToast("Could not copy this clip")
            return
        }
        if prefs.moveToTopOnPaste { store.moveToTop(clip) }
        let shouldType = keystroke && prefs.pasteIntoApp && Accessibility.isTrusted
        let type = {
            if shouldType {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    Paster.shared.sendPasteKeystroke()
                }
            }
        }
        if viewModel.pinned {
            // The panel never activates ClipKeeper, so the keystroke reaches the front app.
            viewModel.showToast(shouldType ? "Pasted" : "Copied")
            type()
        } else {
            hide(completion: type)
        }
    }

    private func edit(_ clip: Clip) {
        let snapshot = store.snapshot(for: clip)
        hide { [store] in
            switch clip.kind {
            case .image:
                guard let snapshot, let data = PBType.imageTypes.compactMap({ snapshot.data(for: $0) }).first else { return }
                CropWindow.present(imageData: data, title: "Crop Image") { png in
                    if let new = store.createImageClip(png: png) { _ = new }
                }
            case .files:
                return
            default:
                let text = snapshot?.string ?? clip.text
                TextEditorWindow.present(text: text, isCode: clip.kind == .code, language: clip.language, title: "Edit Clip") { newText in
                    store.createTextClip(newText, sourceBundleID: clip.sourceBundleID, sourceAppName: clip.sourceAppName)
                }
            }
        }
    }

    /// An empty editor. The text becomes a new clip at the top of the set
    /// that was open in the shelf: History, or a collection.
    func newClip(into set: ClipSet) {
        let store = self.store
        let present = {
            TextEditorWindow.present(text: "", isCode: false, language: nil, title: "New Clip", mode: .new(setName: set.name)) { text in
                guard let clip = store.createTextClip(text) else { return }
                if set.collectionID != nil { store.move([clip], to: set) }
            }
        }
        if isVisible { hide { present() } } else { present() }
    }

    // MARK: Share

    /// Opens the share menu over the shelf, or AirDrop straight away.
    private func share(_ clips: [Clip], airDropOnly: Bool) {
        let ok: Bool
        if airDropOnly {
            ok = Sharer.airDrop(clips, store: store)
        } else {
            let anchor = NSRect(x: hosting.bounds.maxX - 40, y: hosting.bounds.maxY - 44, width: 1, height: 1)
            ok = Sharer.showPicker(for: clips, store: store, in: hosting, at: anchor) { [weak self] in
                self?.viewModel.showSendPicker(for: clips)
            }
        }
        if !ok { viewModel.showToast("Nothing to share") }
    }

    // MARK: Import files

    private lazy var importer = ImportCoordinator(store: store, prefs: prefs)

    /// Imports files as separate clips and shows the outcome. Works whether or
    /// not the shelf is open, so the Finder service and the URL scheme use it too.
    func importFiles(_ urls: [URL], into set: ClipSet) {
        let outcome = importer.importFiles(urls, into: set)
        if outcome.cancelled { return }
        if !isVisible, !outcome.imported.isEmpty {
            show()
        }
        if let idx = viewModel.sets.firstIndex(where: { $0.id == set.id }) { viewModel.selectSet(index: idx) }
        viewModel.reload(keepSelection: false)
        viewModel.select(index: 0)
        viewModel.showToast(outcome.summary)
        if !outcome.problems.isEmpty { NSLog("import skipped: %@", outcome.problems.joined(separator: "; ")) }
    }

    /// Opens the file panel, then imports the chosen files into `set`.
    private func chooseFilesToImport(into set: ClipSet) {
        hide { [weak self] in
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.title = "Import Files into ClipKeeper"
            panel.message = "Each file becomes its own clip. A folder imports its files one level deep."
            panel.prompt = "Import"
            NSApp.activate(ignoringOtherApps: true)
            panel.begin { response in
                guard response == .OK, !panel.urls.isEmpty else { self?.show(); return }
                self?.importFiles(panel.urls, into: set)
            }
        }
    }

    private func saveAs(_ clips: [Clip]) {
        hide { [store, weak self] in
            SaveAsDialog.run(clips: clips, store: store) { saved in
                if saved > 0 { self?.viewModel.showToast(saved == 1 ? "Saved" : "Saved \(saved) files") }
            }
        }
    }
}
