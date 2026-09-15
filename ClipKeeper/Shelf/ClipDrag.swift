import AppKit
import Foundation
import UniformTypeIdentifiers

/// Drag support. A dragged clip carries its content for other apps and a
/// private identifier so a set tab inside the shelf can accept it.
@MainActor
enum ClipDrag {
    static let typeIdentifier = "com.raymondpeck.clipkeeper.clip"

    static func itemProvider(for clip: Clip, store: ClipStore) -> NSItemProvider {
        let provider = NSItemProvider()
        let uuid = Data(clip.uuid.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .ownProcess) { completion in
            completion(uuid, nil)
            return nil
        }
        switch clip.kind {
        case .image:
            if let image = RenderCache.shared.fullImage(for: clip, store: store) {
                provider.registerObject(image, visibility: .all)
            }
        case .files:
            for path in clip.filePaths {
                provider.registerObject(URL(fileURLWithPath: path) as NSURL, visibility: .all)
            }
        default:
            provider.registerObject(clip.text as NSString, visibility: .all)
            if clip.kind == .link, let url = URL(string: clip.text) {
                provider.registerObject(url as NSURL, visibility: .all)
            }
        }
        return provider
    }

    /// Reads the clip identifier from dropped providers.
    static func uuid(from providers: [NSItemProvider], completion: @escaping @MainActor (String?) -> Void) {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(typeIdentifier) }) else {
            completion(nil)
            return
        }
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            let uuid = data.flatMap { String(data: $0, encoding: .utf8) }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(uuid) } }
        }
    }
}
