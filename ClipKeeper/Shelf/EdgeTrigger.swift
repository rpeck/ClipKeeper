import AppKit
import Foundation

/// Opens the shelf when the mouse rests at the right edge of the screen, and
/// closes it again when the mouse leaves the shelf. Works by polling the
/// mouse location, so it needs no permission.
@MainActor
final class EdgeTrigger {
    private let shelf: ShelfController
    private let prefs: Preferences
    private var timer: Timer?
    private var edgeSince: Date?
    private var mouseEnteredShelf = false
    private let edgeWidth: CGFloat = 2
    private let leaveMargin: CGFloat = 24

    init(shelf: ShelfController, prefs: Preferences = .shared) {
        self.shelf = shelf
        self.prefs = prefs
    }

    func start() {
        stop()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard prefs.edgeTriggerEnabled else { edgeSince = nil; return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.screens.first(where: { NSPointInRect(NSPoint(x: mouse.x - 1, y: mouse.y), $0.frame) }) else { return }

        if shelf.isVisible {
            guard shelf.openedByEdge, prefs.edgeAutoHide else { return }
            // A generous frame: the panel plus a margin, extended to the screen edge.
            var zone = shelf.panelFrame.insetBy(dx: -leaveMargin, dy: -leaveMargin)
            zone.size.width = screen.frame.maxX - zone.minX + 1
            let inside = zone.contains(mouse)
            if inside { mouseEnteredShelf = true }
            if mouseEnteredShelf, !inside, NSEvent.pressedMouseButtons == 0 {
                shelf.hide()
                mouseEnteredShelf = false
            }
            return
        }

        // The right edge of the screen that holds the mouse, but not a corner
        // (the corners belong to hot corners).
        let atEdge = mouse.x >= screen.frame.maxX - edgeWidth
            && mouse.y > screen.frame.minY + 8 && mouse.y < screen.frame.maxY - 8
        if atEdge {
            if edgeSince == nil { edgeSince = Date() }
            if Date().timeIntervalSince(edgeSince!) >= prefs.edgeDwell, NSEvent.pressedMouseButtons == 0 {
                edgeSince = nil
                mouseEnteredShelf = false
                shelf.show(on: screen, byEdge: true)
            }
        } else {
            edgeSince = nil
        }
    }
}
