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

    /// The screen is locked. Set by the lock notifications; tests set it directly.
    var screenLocked = ScreenLock.isLocked()
    private var lockObservers: [NSObjectProtocol] = []

    /// How long a change may stay incomplete before it is dropped.
    var settleTimeout: TimeInterval = 2.0

    /// Called after a clip is stored. Used for the menu bar flash.
    var onCapture: ((Clip) -> Void)?

    /// Set CLIPKEEPER_DEBUG=1 to log every capture with its duration.
    nonisolated static let debug = ProcessInfo.processInfo.environment["CLIPKEEPER_DEBUG"] == "1"

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
        watchScreenLock()
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
        for o in lockObservers { DistributedNotificationCenter.default().removeObserver(o) }
        lockObservers = []
    }

    private func watchScreenLock() {
        let center = DistributedNotificationCenter.default()
        lockObservers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked = true }
        })
        lockObservers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenUnlocked() }
        })
    }

    /// After an unlock, what reached the clipboard while it was locked is not
    /// recorded: the current state becomes the baseline.
    func screenUnlocked() {
        screenLocked = false
        pending = nil
        lastChangeCount = pasteboard.changeCount
    }

    /// True for a copy that Universal Clipboard brought from another device,
    /// unless the user opted in to record those.
    private func isFromOtherDevice(_ types: Set<String>) -> Bool {
        !prefs.recordOtherDevices && types.contains(PBType.remoteClipboard)
    }

    /// Reads the pasteboard once. Call it on every tick. Never re-enters.
    func check() {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let count = pasteboard.changeCount

        // While the screen is locked nobody is at the keyboard: consume every
        // change without reading it.
        if screenLocked, !prefs.recordWhileLocked {
            lastChangeCount = count
            pending = nil
            return
        }

        // A new change. Decide at once whether it is ours, paused, or excluded.
        if count != lastChangeCount, pending?.count != count {
            pending = nil
            if prefs.isPaused || count == Paster.shared.lastWrittenChangeCount || isOwnWrite() || isExcludedSource() {
                lastChangeCount = count
                return
            }
            let types = Set((pasteboard.types ?? []).map(\.rawValue))
            // Checked on the declared types, before any data is read, so a copy
            // from another device is not even fetched.
            if isFromOtherDevice(types) {
                if PasteboardMonitor.debug { NSLog("pasteboard change %d skipped: from another device", count) }
                lastChangeCount = count
                return
            }
            if prefs.skipConcealed, types.contains(PBType.concealed) || types.contains(PBType.transient) {
                lastChangeCount = count
                return
            }
            pending = Pending(count: count, snapshot: PasteboardSnapshot.capture(from: pasteboard), since: Date(), reads: 1)
            return
        }

        guard var p = pending else { return }

        // The change is under observation. Read again and compare. A read
        // during which the clipboard changed again is not trusted.
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        guard pasteboard.changeCount == p.count else {
            pending = nil
            return
        }
        if isFromOtherDevice(snapshot.allTypes) {
            lastChangeCount = p.count
            pending = nil
            return
        }
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
        // The last check before the store.
        guard !isFromOtherDevice(snapshot.allTypes), !(screenLocked && !prefs.recordWhileLocked) else { return }

        if let limit = prefs.imageByteLimit, PBType.imageTypes.contains(where: { snapshot.has($0) }), snapshot.totalByteCount > limit {
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        let handoff = snapshot.has(PBType.remoteClipboard)
        if let clip = store.ingest(snapshot, sourceBundleID: front?.bundleIdentifier, sourceAppName: front?.localizedName,
                                   origin: handoff ? Clip.handoffOrigin : nil, sourceDevice: handoff ? Clip.handoffDeviceName : nil) {
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
