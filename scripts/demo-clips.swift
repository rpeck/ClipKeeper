#!/usr/bin/env swift
// Puts a fixed set of sample clips on the general pasteboard, one after
// another, so a running ClipKeeper records them. scripts/refresh-screenshots.sh
// uses it to fill a demo store. Nothing here is personal data.
import AppKit

let pb = NSPasteboard.general

func put(_ items: [NSPasteboard.PasteboardType: Data]) {
    pb.clearContents()
    let item = NSPasteboardItem()
    for (t, d) in items { item.setData(d, forType: t) }
    pb.writeObjects([item])
    Thread.sleep(forTimeInterval: 0.7)
}

// 1. A plain sentence.
put([.string: Data("Meeting moved to 3:30. Bring the Q3 numbers.".utf8)])

// 2. A link.
put([.string: Data("https://developer.apple.com/documentation/swiftui".utf8)])

// 3. Markdown.
let md = """
# Release checklist

- [x] Run the tests
- [ ] Update the **changelog**
- [ ] Tag `v0.1.0`

See the [plan](https://example.com/plan) for details.

```swift
let done = true
```
"""
put([.string: Data(md.utf8)])

// 4. Rich text with a heading, bold, italic, a link, and a list.
let html = "<h2>Meeting notes</h2><p>We agreed on <b>three</b> things and <i>one</i> risk. See <a href=\"https://example.com\">the doc</a>.</p><ul><li>Ship the beta</li><li>Write the release notes</li></ul>"
let attributed = NSAttributedString(html: Data(html.utf8), options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)!
let rtf = try! attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
put([.string: Data(attributed.string.utf8), .rtf: rtf, .html: Data(html.utf8)])

// 5. An image: a gradient with a white disc, 640 × 360.
let w = 640, h = 360
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let colors = [NSColor.systemPink.cgColor, NSColor.systemIndigo.cgColor] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: w, y: h), options: [])
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillEllipse(in: CGRect(x: 220, y: 80, width: 200, height: 200))
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
put([.png: rep.representation(using: .png, properties: [:])!, .tiff: rep.tiffRepresentation!])

// 6. Files.
pb.clearContents()
pb.writeObjects([URL(fileURLWithPath: "/Applications/Safari.app") as NSURL,
                 URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/README.md") as NSURL])
Thread.sleep(forTimeInterval: 0.7)

// 7. A shell command, a color, and JSON.
put([.string: Data("brew install xcodegen && scripts/build-with-xcode.sh run".utf8)])
put([.string: Data("#4cb39a".utf8)])
put([.string: Data("{\"name\": \"ClipKeeper\", \"version\": \"0.1.0\", \"tags\": [\"mac\", \"clipboard\"]}".utf8)])

print("demo clips written")
