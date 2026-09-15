import AppKit
import Foundation

/// Stores the large parts of a clip on disk: the pasteboard snapshot, image
/// thumbnails, and link favicons.
final class BlobStore {
    let root: URL
    private let snapshotsDir: URL
    private let thumbsDir: URL
    private let faviconsDir: URL

    init(root: URL) {
        self.root = root
        snapshotsDir = root.appendingPathComponent("snapshots", isDirectory: true)
        thumbsDir = root.appendingPathComponent("thumbnails", isDirectory: true)
        faviconsDir = root.appendingPathComponent("favicons", isDirectory: true)
        for dir in [root, snapshotsDir, thumbsDir, faviconsDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
    }

    /// Files are private to this user: mode 600.
    private func lock(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func standard() -> BlobStore {
        BlobStore(root: Database.supportDirectory.appendingPathComponent("blobs", isDirectory: true))
    }

    static func temporary() -> BlobStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipKeeperTests-\(UUID().uuidString)")
        return BlobStore(root: dir)
    }

    // MARK: Snapshots

    func snapshotURL(for uuid: String) -> URL {
        snapshotsDir.appendingPathComponent("\(uuid).plist")
    }

    func save(snapshot: PasteboardSnapshot, for uuid: String) throws {
        try snapshot.serialized().write(to: snapshotURL(for: uuid), options: .atomic)
        lock(snapshotURL(for: uuid))
    }

    func loadSnapshot(for uuid: String) -> PasteboardSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL(for: uuid)) else { return nil }
        return PasteboardSnapshot(serialized: data)
    }

    // MARK: Thumbnails

    func thumbnailURL(for uuid: String) -> URL {
        thumbsDir.appendingPathComponent("\(uuid).png")
    }

    /// Makes a PNG thumbnail no wider or taller than `maxDimension` points.
    func saveThumbnail(from imageData: Data, for uuid: String, maxDimension: CGFloat = 800) {
        guard let image = NSImage(data: imageData) else { return }
        let png = ImageConversion.downscaledPNG(image, maxDimension: maxDimension) ?? imageData
        try? png.write(to: thumbnailURL(for: uuid), options: .atomic)
        lock(thumbnailURL(for: uuid))
    }

    func thumbnail(for uuid: String) -> NSImage? {
        NSImage(contentsOf: thumbnailURL(for: uuid))
    }

    // MARK: Favicons

    func faviconURL(forHost host: String) -> URL {
        let safe = host.replacingOccurrences(of: "[^A-Za-z0-9.-]", with: "_", options: .regularExpression)
        return faviconsDir.appendingPathComponent("\(safe).png")
    }

    func favicon(forHost host: String) -> NSImage? {
        NSImage(contentsOf: faviconURL(forHost: host))
    }

    func saveFavicon(_ data: Data, forHost host: String) {
        guard let image = NSImage(data: data), let png = ImageConversion.pngData(image) else { return }
        try? png.write(to: faviconURL(forHost: host), options: .atomic)
        lock(faviconURL(forHost: host))
    }

    // MARK: Removal

    func delete(uuid: String) {
        try? FileManager.default.removeItem(at: snapshotURL(for: uuid))
        try? FileManager.default.removeItem(at: thumbnailURL(for: uuid))
    }

    func duplicate(uuid: String, to newUUID: String) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: snapshotURL(for: uuid).path) {
            try fm.copyItem(at: snapshotURL(for: uuid), to: snapshotURL(for: newUUID))
        }
        if fm.fileExists(atPath: thumbnailURL(for: uuid).path) {
            try fm.copyItem(at: thumbnailURL(for: uuid), to: thumbnailURL(for: newUUID))
        }
    }

    /// Total bytes used by the blob store.
    func totalSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += Int64(size) }
        }
        return total
    }
}
