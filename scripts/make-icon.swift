#!/usr/bin/env swift
// Draws the ClipKeeper app icon and writes the PNG sizes into the asset catalog.
// Usage: swift scripts/make-icon.swift ClipKeeper/Assets.xcassets/AppIcon.appiconset

import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ClipKeeper/Assets.xcassets/AppIcon.appiconset"

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }
    let s = size
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.225

    // Background: deep blue to teal gradient with a soft top highlight.
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.70, blue: 0.78, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: -60)
    let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0), NSColor.white.withAlphaComponent(0.22)])!
    highlight.draw(in: rect, angle: 90)

    // Clipboard board.
    let bw = rect.width * 0.56, bh = rect.height * 0.64
    let board = CGRect(x: rect.midX - bw / 2, y: rect.midY - bh / 2 - rect.height * 0.03, width: bw, height: bh)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSBezierPath(roundedRect: board, xRadius: bw * 0.12, yRadius: bw * 0.12).fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Clip at the top.
    let cw = bw * 0.42, ch = bh * 0.14
    let clip = CGRect(x: board.midX - cw / 2, y: board.maxY - ch * 0.55, width: cw, height: ch)
    NSColor(calibratedRed: 0.13, green: 0.20, blue: 0.35, alpha: 1).setFill()
    NSBezierPath(roundedRect: clip, xRadius: ch * 0.3, yRadius: ch * 0.3).fill()

    // Lines of "content": three rounded bars, the last one an accent.
    let lineH = bh * 0.075
    let lineX = board.minX + bw * 0.16
    let widths: [CGFloat] = [0.68, 0.5, 0.6]
    let colors: [NSColor] = [NSColor(calibratedWhite: 0.70, alpha: 1), NSColor(calibratedWhite: 0.78, alpha: 1), NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.95, alpha: 1)]
    for (i, w) in widths.enumerated() {
        let y = board.maxY - ch * 0.9 - bh * 0.22 - CGFloat(i) * lineH * 2.2
        colors[i].setFill()
        NSBezierPath(roundedRect: CGRect(x: lineX, y: y, width: bw * w, height: lineH), xRadius: lineH / 2, yRadius: lineH / 2).fill()
    }
    image.unlockFocus()
    return image
}

func png(_ image: NSImage, pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (name, px) in sizes {
    let image = draw(size: CGFloat(px))
    if let data = png(image, pixels: px) {
        try? data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
        print("wrote \(name)")
    }
}
