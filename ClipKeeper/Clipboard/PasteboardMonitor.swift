import AppKit
import Foundation

/// Polls the general pasteboard and feeds new copies into the store.
@MainActor
final class PasteboardMonitor {
    private let store: ClipStore
    private let prefs: Preferences
    private var timer: Timer?
    private var lastChangeCount: Int
    private let pasteboard = NSPasteboard.general

    /// Called after a clip is stored. Used for the menu bar flash.
    var onCapture: ((Clip) -> Void)?

    init(store: ClipStore, prefs: Preferences = .shared) {
        self.store = store
        self.prefs = prefs
        lastChangeCount = pasteboard.changeCount
    }

    func start(interval: TimeInterval = 0.15) {
        stop()
        lastChangeCount = pasteboard.changeCount
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private var isChecking = false

    /// Set CLIPKEEPER_DEBUG=1 to log every capture with its duration.
    static let debug = ProcessInfo.processInfo.environment["CLIPKEEPER_DEBUG"] == "1"

    /// Reads the pasteboard once, right now. Never re-enters: a slow ingest
    /// that spins the run loop must not start a second capture.
    func check() {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        let started = Date()
        defer {
            if PasteboardMonitor.debug {
                NSLog("pasteboard change %d handled in %.0f ms", count, Date().timeIntervalSince(started) * 1000)
            }
        }

        if prefs.isPaused { return }
        if count == Paster.shared.lastWrittenChangeCount { return }

        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        if prefs.skipConcealed, types.contains(PBType.concealed) || types.contains(PBType.transient) { return }
        if let source = pasteboard.string(forType: NSPasteboard.PasteboardType(PBType.source)), source == Bundle.main.bundleIdentifier { return }

        let front = NSWorkspace.shared.frontmostApplication
        if let bundle = front?.bundleIdentifier, prefs.excludedBundleIDs.contains(bundle) { return }

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        if PasteboardMonitor.debug { NSLog("  captured %d types in %.0f ms", snapshot.allTypes.count, Date().timeIntervalSince(started) * 1000) }
        guard !snapshot.items.isEmpty else { return }

        if let limit = prefs.imageByteLimit, PBType.imageTypes.contains(where: { snapshot.has($0) }), snapshot.totalByteCount > limit {
            return
        }

        if let clip = store.ingest(snapshot, sourceBundleID: front?.bundleIdentifier, sourceAppName: front?.localizedName) {
            onCapture?(clip)
        }
    }
}
