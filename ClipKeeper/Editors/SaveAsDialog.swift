import AppKit
import Foundation
import UniformTypeIdentifiers

/// Save one clip with a format chooser, or many clips into a folder.
@MainActor
enum SaveAsDialog {
    static func run(clips: [Clip], store: ClipStore, completion: @escaping (Int) -> Void) {
        guard !clips.isEmpty else { completion(0); return }
        NSApp.activate(ignoringOtherApps: true)
        if clips.count == 1 {
            saveOne(clips[0], store: store, completion: completion)
        } else {
            saveMany(clips, store: store, completion: completion)
        }
    }

    private static func saveOne(_ clip: Clip, store: ClipStore, completion: @escaping (Int) -> Void) {
        let snapshot = store.snapshot(for: clip)
        let options = Exporter.options(for: clip, snapshot: snapshot)
        guard !options.isEmpty else { completion(0); return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Save Clip"
        let baseName = Exporter.defaultFileName(for: clip)
        panel.nameFieldStringValue = baseName + "." + options[0].fileExtension
        panel.allowedContentTypes = [options[0].utType]

        let accessory = FormatAccessory(options: options) { option in
            panel.allowedContentTypes = [option.utType]
            let current = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = current + "." + option.fileExtension
        }
        panel.accessoryView = accessory.view

        panel.begin { response in
            guard response == .OK, let url = panel.url else { completion(0); return }
            let option = accessory.selected
            guard let payload = Exporter.payload(for: clip, snapshot: snapshot, option: option) else { completion(0); return }
            do {
                try payload.write(to: url)
                completion(1)
            } catch {
                NSAlert(error: error).runModal()
                completion(0)
            }
        }
    }

    private static func saveMany(_ clips: [Clip], store: ClipStore, completion: @escaping (Int) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Here"
        panel.message = "Save \(clips.count) clips into this folder, each in its original format."
        panel.begin { response in
            guard response == .OK, let dir = panel.url else { completion(0); return }
            var used = Set<String>()
            var saved = 0
            for clip in clips {
                let snapshot = store.snapshot(for: clip)
                guard let option = Exporter.options(for: clip, snapshot: snapshot).first,
                      let payload = Exporter.payload(for: clip, snapshot: snapshot, option: option) else { continue }
                var name = Exporter.defaultFileName(for: clip)
                var candidate = name + "." + option.fileExtension
                var n = 2
                while used.contains(candidate.lowercased()) || FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
                    candidate = "\(name) \(n).\(option.fileExtension)"
                    n += 1
                }
                name = candidate
                used.insert(name.lowercased())
                do {
                    try payload.write(to: dir.appendingPathComponent(name))
                    saved += 1
                } catch {
                    NSLog("save failed for \(name): \(error)")
                }
            }
            completion(saved)
        }
    }
}

/// The format popup shown inside the save panel.
@MainActor
private final class FormatAccessory: NSObject {
    let options: [ExportOption]
    let onChange: (ExportOption) -> Void
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 36))

    var selected: ExportOption { options[max(0, popup.indexOfSelectedItem)] }

    init(options: [ExportOption], onChange: @escaping (ExportOption) -> Void) {
        self.options = options
        self.onChange = onChange
        super.init()
        let label = NSTextField(labelWithString: "Format:")
        label.frame = NSRect(x: 12, y: 9, width: 60, height: 18)
        label.alignment = .right
        popup.frame = NSRect(x: 78, y: 5, width: 260, height: 26)
        for o in options { popup.addItem(withTitle: "\(o.title) (.\(o.fileExtension))") }
        popup.target = self
        popup.action = #selector(changed)
        view.addSubview(label)
        view.addSubview(popup)
    }

    @objc private func changed() {
        onChange(selected)
    }
}
