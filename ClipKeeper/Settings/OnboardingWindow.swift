import AppKit
import KeyboardShortcuts
import SwiftUI

/// First-run window: Accessibility, launch at login, and the hotkey.
@MainActor
final class OnboardingWindowController {
    private(set) var window: NSWindow?
    private let prefs: Preferences

    init(prefs: Preferences = .shared) {
        self.prefs = prefs
    }

    func show(onDone: @escaping () -> Void) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Welcome to ClipKeeper"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: OnboardingView(prefs: prefs) { [weak self] in
            self?.prefs.hasCompletedOnboarding = true
            self?.window?.close()
            self?.window = nil
            onDone()
        })
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {
    @ObservedObject var prefs: Preferences
    let onDone: () -> Void
    // CLIPKEEPER_ONBOARDING_STEP opens a given page, for debug snapshots.
    @State private var step = Int(ProcessInfo.processInfo.environment["CLIPKEEPER_ONBOARDING_STEP"] ?? "") ?? 0
    @State private var trusted = Accessibility.isTrusted
    @State private var loginEnabled = LoginItem.isEnabled
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: accessibility
                case 2: login
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)
            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<4) { i in
                        Circle().fill(i == step ? Color.accentColor : Color.primary.opacity(0.15)).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 { Button("Back") { step -= 1 } }
                if step < 3 {
                    Button(step == 1 && !trusted ? "Skip for Now" : "Continue") { step += 1 }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button("Start Using ClipKeeper") { onDone() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
        .frame(width: 560, height: 620)
        .onReceive(timer) { _ in
            trusted = Accessibility.isTrusted
            loginEnabled = LoginItem.isEnabled
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "clipboard.fill").font(.system(size: 44)).foregroundStyle(Color.accentColor)
            Text("ClipKeeper keeps everything you copy.").font(.title2.weight(.semibold))
            Text("Text, code, Markdown, rich text, images, links, colors, and files all land in the shelf. Press the hotkey, move with the arrow keys, and press Return to paste. Your hands stay on the keyboard.")
                .foregroundStyle(.secondary)
            HStack {
                Text("Hotkey:")
                KeyboardShortcuts.Recorder(for: .toggleShelf)
            }
            Spacer()
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: trusted ? "checkmark.shield.fill" : "hand.raised.fill").font(.system(size: 40)).foregroundStyle(trusted ? .green : Color.accentColor)
            Text("Allow ClipKeeper to paste for you.").font(.title2.weight(.semibold))
            Text("To paste a clip straight into the app you are working in, ClipKeeper presses ⌘V on your behalf. macOS asks for the Accessibility permission for that. Without it, Return copies the clip and you press ⌘V yourself.")
                .foregroundStyle(.secondary)
            if trusted {
                Label("Permission granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                HStack {
                    Button("Open Accessibility Settings") {
                        Accessibility.promptIfNeeded()
                        Accessibility.openSystemSettings()
                    }.buttonStyle(.borderedProminent)
                    Text("Then turn on ClipKeeper in the list.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("You can change this later in Settings › General.").font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var login: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "power").font(.system(size: 40)).foregroundStyle(Color.accentColor)
            Text("Start ClipKeeper when you log in?").font(.title2.weight(.semibold))
            Text("A clipboard manager is only useful when it is running. ClipKeeper lives in the menu bar and uses little memory.")
                .foregroundStyle(.secondary)
            Toggle("Launch ClipKeeper at login", isOn: Binding(get: { loginEnabled }, set: { v in LoginItem.setEnabled(v); loginEnabled = LoginItem.isEnabled }))
                .toggleStyle(.switch)
            if LoginItem.requiresApproval {
                Text("macOS needs your approval in System Settings › General › Login Items.").font(.caption).foregroundStyle(.orange)
            }
            Text("You can change this later in Settings › General.").font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(Color.accentColor)
            Text("You are set.").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                keyLine("⌘⇧V", "Open or close the shelf")
                keyLine("↓ ↑  ⌃N ⌃P  ⌃J ⌃K", "Move between clips")
                keyLine("← →  or  ⌃B ⌃F", "Move between History and your collections")
                keyLine("⏎", "Paste the selected clip")
                keyLine("⇧⏎", "Paste as plain text")
                keyLine("⌘1 – ⌘9", "Paste a slot without moving")
                keyLine("␣", "Full preview")
                keyLine("⌘E", "Edit text or crop an image")
                keyLine("⌘S", "Save the clip as a file")
                keyLine("Mouse", "Rest the pointer at the right screen edge to open the shelf")
            }
            Text("Every key is changeable in Settings › Keys. The menu bar icon has the User Guide.").font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private func keyLine(_ key: String, _ what: String) -> some View {
        HStack(spacing: 10) {
            Text(key).font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                .frame(width: 130, alignment: .leading)
            Text(what).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
