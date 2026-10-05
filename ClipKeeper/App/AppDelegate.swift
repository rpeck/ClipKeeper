import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var database: Database!
    private var store: ClipStore!
    private var monitor: PasteboardMonitor!
    private var shelf: ShelfController!
    private var edgeTrigger: EdgeTrigger!
    private var settings: SettingsWindowController!
    private var transfer: TransferService!
    private var onboarding: OnboardingWindowController?
    private var statusItem: NSStatusItem!
    private var retentionTimer: Timer?
    private var appearanceObservation: NSKeyValueObservation?
    private let prefs = Preferences.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            database = try Database.open()
        } catch {
            let alert = NSAlert()
            alert.messageText = "ClipKeeper cannot open its database."
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        store = ClipStore(database: database, blobs: .standard(), prefs: prefs)
        shelf = ShelfController(store: store, bindings: KeyBindingStore.shared, prefs: prefs)
        transfer = TransferService(store: store, database: database, prefs: prefs)
        transfer.onReceived = { [weak self] in self?.flashStatusItem() }
        shelf.viewModel.transfer = transfer
        settings = SettingsWindowController(store: store, bindings: KeyBindingStore.shared, prefs: prefs, transfer: transfer)
        shelf.openSettings = { [weak self] in self?.settings.show() }
        edgeTrigger = EdgeTrigger(shelf: shelf, prefs: prefs)
        edgeTrigger.start()

        CodeHighlighter.shared.warmUp()
        monitor = PasteboardMonitor(store: store, prefs: prefs)
        monitor.onCapture = { [weak self] _ in self?.flashStatusItem() }
        monitor.start()

        buildMainMenu()
        buildStatusItem()
        transfer.startIfEnabled()

        KeyboardShortcuts.onKeyUp(for: .toggleShelf) { [weak self] in self?.shelf.toggle() }
        KeyboardShortcuts.onKeyUp(for: .eyedropper) { [weak self] in self?.pickColor() }

        retentionTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.applyRetention() }
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in CodeHighlighter.shared.appearanceChanged() }
        }

        let onboardingController = OnboardingWindowController(prefs: prefs)
        onboarding = onboardingController
        if !prefs.hasCompletedOnboarding {
            onboardingController.show {}
        }
        DebugSnapshots.runIfRequested(shelf: shelf, settings: settings, onboarding: onboardingController, store: store)

        // The Finder service "Add to ClipKeeper" and the clipkeeper:// URL scheme.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_:replyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        shelf.show()
        return false
    }

    /// Files dropped on the app icon, or opened with it, become clips.
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter { $0.isFileURL }
        if !files.isEmpty { shelf.importFiles(files, into: shelf.viewModel.currentSet) }
    }

    // MARK: Finder service and URL scheme

    /// The "Add to ClipKeeper" service. Finder calls it with the selected
    /// files on the pasteboard. Users assign it a keyboard shortcut in
    /// System Settings › Keyboard › Keyboard Shortcuts › Services.
    @objc func addToClipKeeper(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else {
            error.pointee = "No files were selected."
            return
        }
        shelf.importFiles(urls, into: shelf.viewModel.currentSet)
    }

    /// clipkeeper://import?path=/a/file&path=/another  — for scripts and automations.
    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string), url.scheme?.lowercased() == "clipkeeper" else { return }
        switch url.host?.lowercased() {
        case "import":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let paths = items.filter { $0.name == "path" }.compactMap(\.value).map { URL(fileURLWithPath: $0) }
            if !paths.isEmpty { shelf.importFiles(paths, into: shelf.viewModel.currentSet) }
        case "show", "open", nil:
            shelf.show()
        default:
            break
        }
    }

    // MARK: Menus

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ClipKeeper", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide ClipKeeper", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit ClipKeeper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipKeeper")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let hotkey = KeyboardShortcuts.getShortcut(for: .toggleShelf)?.description ?? ""
        let open = NSMenuItem(title: "Open Shelf", action: #selector(toggleShelf), keyEquivalent: "")
        open.target = self
        if !hotkey.isEmpty { open.title = "Open Shelf    \(hotkey)" }
        menu.addItem(open)

        let pause = NSMenuItem(title: prefs.isPaused ? "Resume Capture" : "Pause Capture", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let eyedropper = NSMenuItem(title: "Pick a Color with Eyedropper…", action: #selector(pickColor), keyEquivalent: "")
        eyedropper.target = self
        menu.addItem(eyedropper)

        let importItem = NSMenuItem(title: "Import Files as Clips…", action: #selector(importFilesFromMenu), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        menu.addItem(.separator())
        let count = store.historyCount()
        let info = NSMenuItem(title: count == 1 ? "1 clip in History" : "\(count) clips in History", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let guideItem = NSMenuItem(title: "User Guide", action: #selector(openUserGuide), keyEquivalent: "")
        guideItem.target = self
        menu.addItem(guideItem)
        let about = NSMenuItem(title: "About ClipKeeper", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ClipKeeper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func flashStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "ClipKeeper")
        button.image?.isTemplate = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.statusItem.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipKeeper")
            self?.statusItem.button?.image?.isTemplate = true
        }
    }

    // MARK: Actions

    @objc private func toggleShelf() { shelf.toggle() }

    @objc private func togglePause() {
        prefs.isPaused.toggle()
        statusItem.button?.appearsDisabled = prefs.isPaused
    }

    @objc private func openSettings() { settings.show() }

    @objc private func openKeySettings() { settings.show(tab: .keys) }

    @objc private func openUserGuide() {
        if let url = Bundle.main.url(forResource: "USER-GUIDE", withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "https://github.com/rpeck/ClipKeeper/blob/main/docs/USER-GUIDE.md") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func importFilesFromMenu() {
        shelf.viewModel.perform(.importFiles)
    }

    @objc private func pickColor() {
        NSColorSampler().show { [weak self] color in
            guard let color, let self else { return }
            Task { @MainActor in
                if let clip = self.store.createColorClip(color) {
                    let snapshot = self.store.snapshot(for: clip)
                    Paster.shared.copy(clip: clip, variant: .original, original: snapshot)
                    self.flashStatusItem()
                }
            }
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "ClipKeeper",
            .credits: NSAttributedString(string: "A clipboard manager that keeps your hands on the keyboard.", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildStatusMenu(menu)
    }
}
