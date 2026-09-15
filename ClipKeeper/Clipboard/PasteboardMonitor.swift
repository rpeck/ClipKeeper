import AppKit
import Foundation

/// Polls the pasteboard and feeds new copies into the store.
///
/// Apps write the pasteboard in steps: the change count moves when the types
/// are declared, and the data for each type lands afterwards. Chromium
/// encodes a large image to PNG before it sets that type's data. The count
/// never moves again, so a single read taken during the gap would miss the
/// copy for good. The monitor therefore reads twice: it accepts a change only
/// after two consecutive reads return the same complete snapshot.
@MainActor
final class PasteboardMonitor {
    private let store: ClipStore
    private let prefs: Preferences
    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount: Int
    private var isChecking = false

    /// A change under observation, not yet accepted.
    private struct Pending {
        var count: Int
        var snapshot: PasteboardSnapshot
        var since: Date
        var reads: Int
    }
    private var pending: Pending?

    /// How long a change may stay incomplete before it is dropped.
    var settleTimeout: TimeInterval = 2.0

    /// Called after a clip is stored. Used for the menu bar flash.
    var onCapture: ((Clip) -> Void)?

    /// Set CLIPKEEPER_DEBUG=1 to log every capture with its duration.
    static let debug = ProcessInfo.processInfo.environment["CLIPKEEPER_DEBUG"] == "1"

    init(store: ClipStore, prefs: Preferences = .shared, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.prefs = prefs
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    func start(interval: TimeInterval = 0.15) {
        stop()
        lastChangeCount = pasteboard.changeCount
        pending = nil
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

    /// Reads the pasteboard once. Call it on every tick. Never re-enters.
    func check() {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let count = pasteboard.changeCount

        // A new change. Decide at once whether it is ours, paused, or excluded.
        if count != lastChangeCount, pending?.count != count {
            pending = nil
            if prefs.isPaused || count == Paster.shared.lastWrittenChangeCount || isOwnWrite() || isExcludedSource() {
                lastChangeCount = count
                return
            }
            let types = Set((pasteboard.types ?? []).map(\.rawValue))
            if prefs.skipConcealed, types.contains(PBType.concealed) || types.contains(PBType.transient) {
                lastChangeCount = count
                return
            }
            pending = Pending(count: count, snapshot: PasteboardSnapshot.capture(from: pasteboard), since: Date(), reads: 1)
            return
        }

        guard var p = pending else { return }

        // The change is under observation. Read again and compare.
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let stable = snapshot == p.snapshot
        p.snapshot = snapshot
        p.reads += 1
        pending = p

        let complete = !snapshot.items.isEmpty && ContentClassifier.classify(snapshot) != nil
        if stable && complete {
            accept(p)
            return
        }
        if Date().timeIntervalSince(p.since) >= settleTimeout {
            if PasteboardMonitor.debug { NSLog("pasteboard change %d dropped after %d reads: %@", p.count, p.reads, complete ? "unstable" : "incomplete") }
            lastChangeCount = p.count
            pending = nil
        }
    }

    private func accept(_ p: Pending) {
        let started = Date()
        lastChangeCount = p.count
        pending = nil
        let snapshot = p.snapshot

        if let limit = prefs.imageByteLimit, PBType.imageTypes.contains(where: { snapshot.has($0) }), snapshot.totalByteCount > limit {
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        if let clip = store.ingest(snapshot, sourceBundleID: front?.bundleIdentifier, sourceAppName: front?.localizedName) {
            onCapture?(clip)
        }
        if PasteboardMonitor.debug {
            NSLog("pasteboard change %d accepted after %d reads, %d types, stored in %.0f ms", p.count, p.reads, snapshot.allTypes.count, Date().timeIntervalSince(started) * 1000)
        }
    }

    private func isOwnWrite() -> Bool {
        guard let source = pasteboard.string(forType: NSPasteboard.PasteboardType(PBType.source)) else { return false }
        return source == Bundle.main.bundleIdentifier
    }

    private func isExcludedSource() -> Bool {
        guard let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return prefs.excludedBundleIDs.contains(bundle)
    }
}
