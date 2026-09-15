import AppKit
import Foundation

/// Development aid. When the environment variable CLIPKEEPER_SNAPSHOT_DIR is
/// set, the app renders its main views to PNG files in that directory shortly
/// after launch. With CLIPKEEPER_SNAPSHOT_QUIT=1 it then quits. The files
/// double as the screenshots in the User Guide.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(shelf: ShelfController, settings: SettingsWindowController, onboarding: OnboardingWindowController, store: ClipStore) {
        guard let dir = ProcessInfo.processInfo.environment["CLIPKEEPER_SNAPSHOT_DIR"], !dir.isEmpty else { return }
        let quit = ProcessInfo.processInfo.environment["CLIPKEEPER_SNAPSHOT_QUIT"] == "1"
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        var steps: [(TimeInterval, () -> Void)] = []
        let vm = shelf.viewModel
        func shot(_ name: String) { write(shelf.snapshotView, to: url.appendingPathComponent(name)) }
        func selectFirst(kind: ClipKind) {
            if let idx = vm.clips.firstIndex(where: { $0.kind == kind }) { vm.select(index: idx) }
        }

        steps.append((1.0, { shelf.show() }))
        steps.append((1.5, { shot("shelf.png") }))
        steps.append((0.2, { selectFirst(kind: .image); vm.perform(.togglePreview) }))
        steps.append((0.8, { shot("preview-image.png"); vm.perform(.togglePreview) }))
        steps.append((0.2, { selectFirst(kind: .markdown); vm.perform(.togglePreview) }))
        steps.append((0.8, { shot("preview.png"); vm.perform(.togglePreview); vm.select(index: 0) }))
        steps.append((0.2, { vm.perform(.moveToCollection) }))
        steps.append((0.6, { shot("picker.png"); vm.overlay = nil }))
        steps.append((0.2, { vm.query = "release" }))
        steps.append((0.8, { shot("search.png"); vm.query = "" }))
        steps.append((0.2, { vm.perform(.toggleSelectMode); vm.perform(.extendSelectionDown); vm.perform(.extendSelectionDown) }))
        steps.append((0.6, { shot("checked.png"); vm.perform(.selectAll); vm.perform(.selectAll) }))
        steps.append((0.2, { vm.perform(.delete) }))
        steps.append((0.6, { shot("confirm.png"); vm.overlay = nil; shelf.hide() }))
        steps.append((0.5, { settings.show(tab: .general) }))
        steps.append((1.0, {
            if let v = settings.window?.contentView { write(v, to: url.appendingPathComponent("settings.png")) }
            settings.show(tab: .keys)
        }))
        steps.append((0.8, {
            if let v = settings.window?.contentView { write(v, to: url.appendingPathComponent("settings-keys.png")) }
            settings.show(tab: .storage)
        }))
        steps.append((0.8, {
            if let v = settings.window?.contentView { write(v, to: url.appendingPathComponent("settings-storage.png")) }
            settings.window?.close()
            onboarding.show {}
        }))
        steps.append((1.0, {
            if let v = onboarding.window?.contentView { write(v, to: url.appendingPathComponent("onboarding.png")) }
            onboarding.window?.close()
            TextEditorWindow.present(text: "def hello(name):\n    print(f\"hi {name}\")\n", isCode: true, language: "python", title: "Edit Clip") { _ in }
        }))
        steps.append((1.0, {
            if let w = NSApp.windows.first(where: { $0.title == "Edit Clip" }), let v = w.contentView {
                write(v, to: url.appendingPathComponent("editor.png"))
                w.close()
            }
            if let clip = store.clips(in: .history, query: "").first(where: { $0.kind == .image }),
               let snap = store.snapshot(for: clip), let data = PBType.imageTypes.compactMap({ snap.data(for: $0) }).first {
                CropWindow.present(imageData: data, title: "Crop Image") { _ in }
            }
        }))
        steps.append((1.0, {
            if let w = NSApp.windows.first(where: { $0.title == "Crop Image" }), let v = w.contentView {
                write(v, to: url.appendingPathComponent("crop.png"))
                w.close()
            }
            if quit { NSApp.terminate(nil) }
        }))

        var delay: TimeInterval = 0
        for (wait, action) in steps {
            delay += wait
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    }

    private static func write(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
}
