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

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var seenDragCount = NSPasteboard(name: .drag).changeCount

    /// True while the mouse button is down and a drag that carries file URLs
    /// is in progress. The drag pasteboard's change count moves when a drag
    /// starts, and its contents stay after the drop, so the count is compared
    /// to the last one seen with the button up.
    private func isDraggingFiles() -> Bool {
        if NSEvent.pressedMouseButtons == 0 {
            seenDragCount = dragPasteboard.changeCount
            return false
        }
        guard dragPasteboard.changeCount != seenDragCount else { return false }
        return dragPasteboard.types?.contains(.fileURL) ?? false
    }

    private func tick() {
        guard prefs.edgeTriggerEnabled else { edgeSince = nil; return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: mouse.x - 1, y: mouse.y)) }) else { return }

        if shelf.isVisible {
            guard shelf.openedByEdge, prefs.edgeAutoHide, !prefs.shelfPinned else { return }
            // A send in progress waits for the user, who may be at the other device.
            guard !shelf.viewModel.holdsShelfOpenForTransfer else { return }
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
            let since = edgeSince ?? Date()
            edgeSince = since
            // Open with the button up, or during a file drag so the files can
            // be dropped on the shelf. A window drag does not open it.
            let buttonUp = NSEvent.pressedMouseButtons == 0
            if Date().timeIntervalSince(since) >= prefs.edgeDwell, buttonUp || isDraggingFiles() {
                edgeSince = nil
                mouseEnteredShelf = false
                shelf.show(on: screen, byEdge: true)
            }
        } else {
            edgeSince = nil
        }
    }
}
