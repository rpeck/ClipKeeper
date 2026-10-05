import AppKit
import SwiftUI

/// A window for editing a text clip, or for typing a new one. Saving makes
/// a new clip; an edited original stays.
@MainActor
enum TextEditorWindow {
    enum Mode {
        case edit
        case new(setName: String)
    }

    private static var windows: [NSWindow] = []

    static func present(text: String, isCode: Bool, language: String?, title: String, mode: Mode = .edit, onSave: @escaping (String) -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 300)
        let view = TextEditorView(text: text, isCode: isCode, language: language, mode: mode) { result in
            if let result { onSave(result) }
            window.close()
        }
        window.contentView = NSHostingView(rootView: view)
        window.center()
        windows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            Task { @MainActor in windows.removeAll { $0 === window } }
        }
    }
}

struct TextEditorView: View {
    @State var text: String
    let isCode: Bool
    let language: String?
    var mode: TextEditorWindow.Mode = .edit
    let onFinish: (String?) -> Void
    @State private var original: String = ""
    @FocusState private var focused: Bool

    private var note: String {
        switch mode {
        case .edit: return "Saving makes a new clip on top of History. The original stays."
        case .new(let setName): return "Saving adds this text as a clip on top of \(setName). ⌘⏎ saves."
        }
    }

    private var saveTitle: String {
        switch mode {
        case .edit: return "Save as New Clip"
        case .new: return "Add Clip"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(isCode ? .system(size: 13, design: .monospaced) : .system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .focused($focused)
            Divider()
            HStack {
                if isCode, let lang = CodeLanguage.named(language)?.displayName {
                    Text(lang).font(.caption).foregroundStyle(.secondary)
                }
                Text(note)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(saveTitle) { onFinish(text) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text == original)
            }
            .padding(10)
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            original = text
            DispatchQueue.main.async { focused = true }
        }
    }
}
