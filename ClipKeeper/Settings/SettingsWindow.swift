import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleShelf = Self("toggleShelf", default: .init(.v, modifiers: [.control, .command]))
    static let eyedropper = Self("eyedropper")
}

enum SettingsTab: String, Hashable {
    case general, keys, privacy, storage
}

/// The selected settings tab, shared so menu items can open a specific tab.
@MainActor
final class SettingsSelection: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// Owns the Settings window.
@MainActor
final class SettingsWindowController {
    private(set) var window: NSWindow?
    private let store: ClipStore
    private let bindings: KeyBindingStore
    private let prefs: Preferences
    private let selection = SettingsSelection()
    private var escapeMonitor: Any?

    /// True while the Keys tab records a key combination. Escape then cancels
    /// the recording instead of closing the window.
    static var isRecordingKeys = false

    init(store: ClipStore, bindings: KeyBindingStore, prefs: Preferences = .shared) {
        self.store = store
        self.bindings = bindings
        self.prefs = prefs
    }

    func show(tab: SettingsTab? = nil) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "ClipKeeper Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(store: store, bindings: bindings, prefs: prefs, selection: selection))
            w.center()
            window = w
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.keyCode == 53, event.window === self.window, !SettingsWindowController.isRecordingKeys else { return event }
                self.window?.close()
                return nil
            }
        }
        if let tab { selection.tab = tab }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let store: ClipStore
    @ObservedObject var bindings: KeyBindingStore
    @ObservedObject var prefs: Preferences
    @ObservedObject var selection: SettingsSelection

    var body: some View {
        TabView(selection: $selection.tab) {
            GeneralSettingsView(prefs: prefs)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            KeybindingsSettingsView(bindings: bindings)
                .tabItem { Label("Keys", systemImage: "keyboard") }
                .tag(SettingsTab.keys)
            PrivacySettingsView(prefs: prefs)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag(SettingsTab.privacy)
            StorageSettingsView(store: store, prefs: prefs)
                .tabItem { Label("Storage", systemImage: "internaldrive") }
                .tag(SettingsTab.storage)
        }
        .frame(width: 620, height: 560)
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

/// One action in the Keys tab: its combos, an add button, and a reset button.
struct KeyBindingRow: View {
    let action: KeyAction
    let combos: [KeyCombo]
    let isRecording: Bool
    let isDefault: Bool
    let onRemove: (KeyCombo) -> Void
    let onToggleRecording: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack {
            Text(action.title).frame(width: 190, alignment: .leading)
            FlowLayout(spacing: 4, rowSpacing: 4) {
                ForEach(combos, id: \.self) { combo in
                    comboChip(combo)
                }
                if combos.isEmpty {
                    Text("none").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button(action: onToggleRecording) {
                Text(isRecording ? "Press keys…" : "+")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minWidth: 22)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(isRecording ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Add a key combination for this action")
            Button("Reset", action: onReset)
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isDefault)
                .help("Restore the default keys for this action")
        }
        .padding(.vertical, 2)
    }

    private func comboChip(_ combo: KeyCombo) -> some View {
        HStack(spacing: 3) {
            Text(combo.description).font(.system(size: 12, weight: .medium, design: .rounded))
            Button { onRemove(combo) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Remove this key combination")
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct KeybindingsSettingsView: View {
    @ObservedObject var bindings: KeyBindingStore
    @State private var recording: KeyAction?
    @State private var monitor: Any?

    private var groups: [(String, [KeyAction])] {
        let order = ["Navigation", "Paste", "Slots", "Clip", "Selection", "Collections"]
        return order.map { g in (g, KeyAction.allCases.filter { $0.group == g }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(groups, id: \.0) { group, actions in
                    Section(group) {
                        ForEach(actions) { action in
                            KeyBindingRow(
                                action: action,
                                combos: bindings.combos(for: action),
                                isRecording: recording == action,
                                isDefault: bindings.combos(for: action) == action.defaultCombos,
                                onRemove: { bindings.remove($0, from: action) },
                                onToggleRecording: { if recording == action { stopRecording() } else { startRecording(action) } },
                                onReset: { bindings.resetToDefaults(action) }
                            )
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text(statusText)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset All to Defaults") { bindings.resetAll() }
            }
            .padding(10)
        }
        .onDisappear { stopRecording() }
    }

    private var statusText: String {
        if let recording {
            return "Recording for “\(recording.title)”. Press the keys, or Esc to cancel."
        }
        return "Click + at the right of an action, then press the keys. Esc cancels. A key combination belongs to one action."
    }

    private func startRecording(_ action: KeyAction) {
        stopRecording()
        recording = action
        SettingsWindowController.isRecordingKeys = true
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
        SettingsWindowController.isRecordingKeys = false
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
                limitRow(label: "Keep at most", unit: "clips in History",
                         enabled: Binding(get: { prefs.historyLimitEnabled }, set: { prefs.historyLimitEnabled = $0; store.applyRetention() }),
                         value: Binding(get: { prefs.historyLimit }, set: { prefs.historyLimit = $0 }))
                limitRow(label: "Delete clips older than", unit: "days",
                         enabled: Binding(get: { prefs.ageLimitEnabled }, set: { prefs.ageLimitEnabled = $0; store.applyRetention() }),
                         value: Binding(get: { prefs.ageLimitDays }, set: { prefs.ageLimitDays = $0 }))
                Text(ruleText).font(.caption).foregroundStyle(.secondary)
            }
            Section("Images") {
                limitRow(label: "Skip images larger than", unit: "MB",
                         enabled: Binding(get: { prefs.imageLimitEnabled }, set: { prefs.imageLimitEnabled = $0 }),
                         value: Binding(get: { prefs.imageLimitMB }, set: { prefs.imageLimitMB = $0 }))
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

    /// One line: a switch, the label, the number, the unit, and "Unlimited" when off.
    private func limitRow(label: String, unit: String, enabled: Binding<Bool>, value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: enabled).labelsHidden()
            Text(label)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .disabled(!enabled.wrappedValue)
            Text(unit)
            Spacer()
            Text(enabled.wrappedValue ? "" : "Unlimited").foregroundStyle(.secondary)
        }
        .foregroundStyle(enabled.wrappedValue ? .primary : .secondary)
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
