import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleShelf = Self("toggleShelf", default: .init(.v, modifiers: [.command, .shift]))
    static let eyedropper = Self("eyedropper")
}

/// Owns the Settings window.
@MainActor
final class SettingsWindowController {
    private(set) var window: NSWindow?
    private let store: ClipStore
    private let bindings: KeyBindingStore
    private let prefs: Preferences

    init(store: ClipStore, bindings: KeyBindingStore, prefs: Preferences = .shared) {
        self.store = store
        self.bindings = bindings
        self.prefs = prefs
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 520), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "ClipKeeper Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(store: store, bindings: bindings, prefs: prefs))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let store: ClipStore
    @ObservedObject var bindings: KeyBindingStore
    @ObservedObject var prefs: Preferences

    var body: some View {
        TabView {
            GeneralSettingsView(prefs: prefs)
                .tabItem { Label("General", systemImage: "gearshape") }
            KeybindingsSettingsView(bindings: bindings)
                .tabItem { Label("Keys", systemImage: "keyboard") }
            PrivacySettingsView(prefs: prefs)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            StorageSettingsView(store: store, prefs: prefs)
                .tabItem { Label("Storage", systemImage: "internaldrive") }
        }
        .frame(width: 620, height: 520)
    }
}

// MARK: General

struct GeneralSettingsView: View {
    @ObservedObject var prefs: Preferences
    @State private var accessibilityTrusted = Accessibility.isTrusted
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginError: String?
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Hotkeys") {
                KeyboardShortcuts.Recorder("Show or hide the shelf:", name: .toggleShelf)
                KeyboardShortcuts.Recorder("Pick a color with the eyedropper:", name: .eyedropper)
            }
            Section("Pasting") {
                Toggle("Paste into the front app when I press Return", isOn: Binding(get: { prefs.pasteIntoApp }, set: { prefs.pasteIntoApp = $0 }))
                Text("When off, Return copies the clip to the clipboard and closes the shelf. You then press ⌘V.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityTrusted ? .green : .orange)
                    Text(accessibilityTrusted ? "Accessibility permission is granted." : "Accessibility permission is needed to paste into other apps.")
                    Spacer()
                    if !accessibilityTrusted {
                        Button("Request Permission") { Accessibility.promptIfNeeded() }
                    }
                    Button("Open System Settings") { Accessibility.openSystemSettings() }
                }
                if !accessibilityTrusted {
                    Text("If ClipKeeper is already on in the Accessibility list but this warning stays, the entry belongs to an older build. Remove ClipKeeper from the list with the − button, then click Request Permission.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Move a clip to the top of History after pasting it", isOn: Binding(get: { prefs.moveToTopOnPaste }, set: { prefs.moveToTopOnPaste = $0 }))
            }
            Section("Shelf") {
                Slider(value: Binding(get: { prefs.shelfWidth }, set: { prefs.shelfWidth = $0 }), in: 200...800, step: 10) {
                    Text("Width: \(Int(prefs.shelfWidth)) pt")
                }
                Toggle("Ask before deleting clips", isOn: Binding(get: { prefs.confirmDelete }, set: { prefs.confirmDelete = $0 }))
            }
            Section("Mouse") {
                Toggle("Open the shelf when the mouse rests at the right edge of the screen", isOn: Binding(get: { prefs.edgeTriggerEnabled }, set: { prefs.edgeTriggerEnabled = $0 }))
                Slider(value: Binding(get: { prefs.edgeDwell }, set: { prefs.edgeDwell = $0 }), in: 0...1.5, step: 0.05) {
                    Text("Delay: \(String(format: "%.2f", prefs.edgeDwell)) s")
                }
                .disabled(!prefs.edgeTriggerEnabled)
                Toggle("Close the shelf again when the mouse leaves it", isOn: Binding(get: { prefs.edgeAutoHide }, set: { prefs.edgeAutoHide = $0 }))
                    .disabled(!prefs.edgeTriggerEnabled)
                Text("The hotkey still works. A shelf opened with the hotkey stays until you close it.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch ClipKeeper at login", isOn: Binding(get: { loginEnabled }, set: { value in
                    if let err = LoginItem.setEnabled(value) { loginError = err.localizedDescription } else { loginError = nil }
                    loginEnabled = LoginItem.isEnabled
                }))
                if LoginItem.requiresApproval {
                    Text("macOS needs your approval in System Settings › General › Login Items.").font(.caption).foregroundStyle(.orange)
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            accessibilityTrusted = Accessibility.isTrusted
            loginEnabled = LoginItem.isEnabled
        }
    }
}

// MARK: Keybindings

struct KeybindingsSettingsView: View {
    @ObservedObject var bindings: KeyBindingStore
    @State private var recording: KeyAction? = nil
    @State private var monitor: Any? = nil

    private var groups: [(String, [KeyAction])] {
        let order = ["Navigation", "Paste", "Slots", "Clip", "Selection"]
        return order.map { g in (g, KeyAction.allCases.filter { $0.group == g }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(groups, id: \.0) { group, actions in
                    Section(group) {
                        ForEach(actions) { action in
                            HStack {
                                Text(action.title).frame(width: 190, alignment: .leading)
                                FlowLayout(spacing: 4, rowSpacing: 4) {
                                    ForEach(bindings.combos(for: action), id: \.self) { combo in
                                        HStack(spacing: 3) {
                                            Text(combo.description).font(.system(size: 12, weight: .medium, design: .rounded))
                                            Button { bindings.remove(combo, from: action) } label: {
                                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                            }
                                            .buttonStyle(.plain).foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                                    }
                                    Button {
                                        if recording == action { stopRecording() } else { startRecording(action) }
                                    } label: {
                                        Text(recording == action ? "Press keys…" : "+")
                                            .font(.system(size: 11, weight: .semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(recording == action ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer()
                                Button("Reset") { bindings.resetToDefaults(action) }
                                    .font(.caption)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .disabled(bindings.combos(for: action) == action.defaultCombos)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text(recording == nil ? "Click + next to an action, then press the keys. Esc cancels. A key combo belongs to one action." : "Recording for “\(recording!.title)”. Press the keys, or Esc to cancel.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset All to Defaults") { bindings.resetAll() }
            }
            .padding(10)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording(_ action: KeyAction) {
        stopRecording()
        recording = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let current = recording else { return event }
            if event.keyCode == 53 { stopRecording(); return nil }
            if let combo = KeyCombo(event: event) {
                bindings.add(combo, to: current)
                stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}

// MARK: Privacy

struct PrivacySettingsView: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Skip clips that password managers mark as concealed or transient", isOn: Binding(get: { prefs.skipConcealed }, set: { prefs.skipConcealed = $0 }))
                Toggle("Fetch page titles and icons for copied links", isOn: Binding(get: { prefs.fetchLinkTitles }, set: { prefs.fetchLinkTitles = $0 }))
                Text("Fetching a title sends one request to the link's site.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Excluded apps") {
                Text("Copies made in these apps are not recorded.").font(.caption).foregroundStyle(.secondary)
                ForEach(prefs.excludedBundleIDs, id: \.self) { id in
                    HStack {
                        if let icon = AppIcons.icon(forBundleID: id) { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                        Text(appName(for: id))
                        Text(id).font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        Button { prefs.excludedBundleIDs.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                Button("Add App…") { addApp() }
            }
        }
        .formStyle(.grouped)
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
            if !prefs.excludedBundleIDs.contains(id) { prefs.excludedBundleIDs.append(id) }
        }
    }
}

// MARK: Storage

struct StorageSettingsView: View {
    let store: ClipStore
    @ObservedObject var prefs: Preferences
    @State private var usage: String = ""
    @State private var count: Int = 0
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("History limits") {
                Toggle("Keep at most", isOn: Binding(get: { prefs.historyLimitEnabled }, set: { prefs.historyLimitEnabled = $0; store.applyRetention() }))
                HStack {
                    TextField("Count", value: Binding(get: { prefs.historyLimit }, set: { prefs.historyLimit = $0 }), format: .number)
                        .frame(width: 80)
                        .disabled(!prefs.historyLimitEnabled)
                    Text("clips in History").foregroundStyle(prefs.historyLimitEnabled ? .primary : .secondary)
                    Spacer()
                    if !prefs.historyLimitEnabled { Text("Unlimited").foregroundStyle(.secondary) }
                }
                Toggle("Delete clips older than", isOn: Binding(get: { prefs.ageLimitEnabled }, set: { prefs.ageLimitEnabled = $0; store.applyRetention() }))
                HStack {
                    TextField("Days", value: Binding(get: { prefs.ageLimitDays }, set: { prefs.ageLimitDays = $0 }), format: .number)
                        .frame(width: 80)
                        .disabled(!prefs.ageLimitEnabled)
                    Text("days").foregroundStyle(prefs.ageLimitEnabled ? .primary : .secondary)
                    Spacer()
                    if !prefs.ageLimitEnabled { Text("Unlimited").foregroundStyle(.secondary) }
                }
                Text(ruleText).font(.caption).foregroundStyle(.secondary)
            }
            Section("Images") {
                Toggle("Skip images larger than", isOn: Binding(get: { prefs.imageLimitEnabled }, set: { prefs.imageLimitEnabled = $0 }))
                HStack {
                    TextField("MB", value: Binding(get: { prefs.imageLimitMB }, set: { prefs.imageLimitMB = $0 }), format: .number)
                        .frame(width: 80)
                        .disabled(!prefs.imageLimitEnabled)
                    Text("MB").foregroundStyle(prefs.imageLimitEnabled ? .primary : .secondary)
                    Spacer()
                    if !prefs.imageLimitEnabled { Text("Unlimited").foregroundStyle(.secondary) }
                }
            }
            Section("Usage") {
                HStack {
                    Text("\(count) clips · \(usage) on disk")
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Database.supportDirectory]) }
                    Button("Clear History…") { confirmClear = true }
                }
                Text("Clear History removes unpinned clips from History. Collections and pinned clips stay.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onChange(of: store.changeToken) { _, _ in refresh() }
        .confirmationDialog("Clear all unpinned clips from History?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { store.clearHistory() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var ruleText: String {
        switch (prefs.historyLimitEnabled, prefs.ageLimitEnabled) {
        case (true, true): return "Rule: a clip is deleted when it is past the count limit OR older than \(prefs.ageLimitDays) days. Either condition is enough. Pinned clips and clips in collections are never deleted by these limits."
        case (true, false): return "Rule: the oldest unpinned clips are deleted once History has more than \(prefs.historyLimit). Pinned clips and clips in collections are never deleted by this limit."
        case (false, true): return "Rule: unpinned clips older than \(prefs.ageLimitDays) days are deleted. Pinned clips and clips in collections are never deleted by this limit."
        case (false, false): return "Rule: nothing is deleted automatically."
        }
    }

    private func refresh() {
        count = store.totalCount()
        usage = ByteCountFormatter.string(fromByteCount: store.storageBytes(), countStyle: .file)
    }
}
