import AppKit
import SwiftUI

/// Shows an attributed string in an NSTextView. Used for the full preview of
/// rich text, where attachments and exact layout matter.
struct RichTextView: NSViewRepresentable {
    let attributed: NSAttributedString
    var selectable: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = selectable
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(attributed)
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.textStorage?.isEqual(to: attributed) == false {
            textView.textStorage?.setAttributedString(attributed)
        }
        textView.isSelectable = selectable
    }
}
