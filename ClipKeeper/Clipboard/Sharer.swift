import AppKit
import Foundation

/// Sends clips through the system share sheet or straight to AirDrop.
/// A text clip travels as text, a link as a URL, and everything else as a
/// file in its default export format, so the receiver gets the right type.
@MainActor
enum Sharer {
    /// The items to hand to a sharing service.
    static func items(for clips: [Clip], store: ClipStore) -> [Any] {
        var items: [Any] = []
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipKeeper-Share-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for clip in clips {
            switch clip.kind {
            case .text, .markdown, .code:
                if clips.count == 1 {
                    items.append(clip.text as NSString)
                    continue
                }
                if let url = exportFile(clip, store: store, in: dir) { items.append(url as NSURL) }
            case .link:
                if let url = URL(string: clip.text) { items.append(url as NSURL) }
            case .files:
                for path in clip.filePaths { items.append(URL(fileURLWithPath: path) as NSURL) }
            case .color:
                items.append((clip.colorHex ?? clip.text) as NSString)
            case .richText, .image:
                if let url = exportFile(clip, store: store, in: dir) { items.append(url as NSURL) }
            }
        }
        return items
    }

    private static func exportFile(_ clip: Clip, store: ClipStore, in dir: URL) -> URL? {
        let snapshot = store.snapshot(for: clip)
        guard let option = Exporter.options(for: clip, snapshot: snapshot).first,
              let payload = Exporter.payload(for: clip, snapshot: snapshot, option: option) else { return nil }
        let name = Exporter.defaultFileName(for: clip) + "." + option.fileExtension
        let url = dir.appendingPathComponent(name)
        do {
            try payload.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Opens AirDrop with the clips. Returns false when there is nothing to send.
    @discardableResult
    static func airDrop(_ clips: [Clip], store: ClipStore) -> Bool {
        let items = items(for: clips, store: store)
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: items) else { return false }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: items)
        return true
    }

    /// Opens the share menu (AirDrop, Messages, Mail, Notes, …) anchored to a
    /// view. `sendToDevice`, when given, adds "Send to a Phone or Mac…".
    @discardableResult
    static func showPicker(for clips: [Clip], store: ClipStore, in view: NSView, at rect: NSRect, sendToDevice: (() -> Void)? = nil) -> Bool {
        let items = items(for: clips, store: store)
        guard !items.isEmpty else { return false }
        let picker = NSSharingServicePicker(items: items)
        let delegate = SharePickerDelegate(sendToDevice: sendToDevice)
        picker.delegate = delegate
        activeDelegate = delegate
        picker.show(relativeTo: rect, of: view, preferredEdge: .minX)
        return true
    }

    /// The picker holds its delegate weakly; this keeps it alive while the menu is open.
    private static var activeDelegate: SharePickerDelegate?
}

/// Adds ClipKeeper's own send to the system share menu.
final class SharePickerDelegate: NSObject, NSSharingServicePickerDelegate {
    let sendToDevice: (() -> Void)?

    init(sendToDevice: (() -> Void)?) {
        self.sendToDevice = sendToDevice
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any], proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService] {
        guard let sendToDevice else { return proposedServices }
        let image = NSImage(systemSymbolName: "iphone.and.arrow.forward", accessibilityDescription: nil) ?? NSImage()
        let service = NSSharingService(title: "Send to a Phone or Mac…", image: image, alternateImage: nil) {
            DispatchQueue.main.async { sendToDevice() }
        }
        return [service] + proposedServices
    }
}
