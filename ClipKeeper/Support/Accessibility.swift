import AppKit
import ApplicationServices
import Foundation

/// Accessibility permission helpers. ClipKeeper needs the permission only to
/// send ⌘V to the front app.
enum Accessibility {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that offers to open the Accessibility pane.
    static func promptIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The frame of the focused window of the front app, in screen coordinates
    /// with a bottom-left origin. Needs Accessibility. Returns nil otherwise.
    static func focusedWindowFrame() -> CGRect? {
        guard isTrusted, let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &window) == .success, let win = window else { return nil }
        let axWindow = win as! AXUIElement
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let p = posRef, let s = sizeRef else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        // AX coordinates have a top-left origin on the main display. Flip to AppKit.
        guard let main = NSScreen.screens.first else { return nil }
        let flippedY = main.frame.height - point.y - size.height
        return CGRect(x: point.x, y: flippedY, width: size.width, height: size.height)
    }
}
