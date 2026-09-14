import AppKit
import SwiftUI

/// A window for editing a text clip. Saving makes a new clip; the original stays.
@MainActor
enum TextEditorWindow {
    private static var windows: [NSWindow] = []

    static func present(text: String, isCode: Bool, language: String?, title: String, onSave: @escaping (String) -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 300)
        let view = TextEditorView(text: text, isCode: isCode, language: language) { result in
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
    let onFinish: (String?) -> Void
    @State private var original: String = ""

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(isCode ? .system(size: 13, design: .monospaced) : .system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
            Divider()
            HStack {
                if isCode, let lang = CodeLanguage.named(language)?.displayName {
                    Text(lang).font(.caption).foregroundStyle(.secondary)
                }
                Text("Saving makes a new clip on top of History. The original stays.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Save as New Clip") { onFinish(text) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text == original)
            }
            .padding(10)
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { original = text }
    }
}
