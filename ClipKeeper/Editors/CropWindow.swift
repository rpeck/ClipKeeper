import AppKit
import SwiftUI

/// A window for cropping an image clip. Saving makes a new clip; the original stays.
@MainActor
enum CropWindow {
    private static var windows: [NSWindow] = []

    static func present(imageData: Data, title: String, onSave: @escaping (Data) -> Void) {
        guard let image = NSImage(data: imageData), let pixels = ImageConversion.pixelSize(of: imageData) else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 360)
        let view = CropView(image: image, pixelSize: pixels) { rect in
            if let rect, let png = ImageConversion.crop(imageData, to: rect) { onSave(png) }
            window.close()
        }
        window.contentView = NSHostingView(rootView: view)
        window.center()
        windows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            Task { @MainActor in windows.removeAll { $0 === window } }
        }
    }
}

struct CropView: View {
    let image: NSImage
    let pixelSize: CGSize
    let onFinish: (CGRect?) -> Void

    /// Crop rect in pixel coordinates, origin top-left.
    @State private var crop: CGRect
    @State private var dragStart: CGRect? = nil

    init(image: NSImage, pixelSize: CGSize, onFinish: @escaping (CGRect?) -> Void) {
        self.image = image
        self.pixelSize = pixelSize
        self.onFinish = onFinish
        _crop = State(initialValue: CGRect(origin: .zero, size: pixelSize))
    }

    private var isWhole: Bool { crop.integral == CGRect(origin: .zero, size: pixelSize).integral }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let fit = fittedRect(in: geo.size)
                let scale = fit.width / pixelSize.width
                ZStack(alignment: .topLeading) {
                    CheckerboardBackground()
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .offset(x: fit.minX, y: fit.minY)
                    // Dim outside the crop.
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: geo.size))
                        p.addRect(viewRect(crop, fit: fit, scale: scale))
                    }
                    .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    cropOverlay(fit: fit, scale: scale)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let start = pixelPoint(value.startLocation, fit: fit, scale: scale)
                            let current = pixelPoint(value.location, fit: fit, scale: scale)
                            if dragStart == nil {
                                dragStart = crop.contains(start) ? crop : .null
                            }
                            if let ds = dragStart, !ds.isNull {
                                let delta = CGPoint(x: current.x - start.x, y: current.y - start.y)
                                crop = clamp(CGRect(x: ds.minX + delta.x, y: ds.minY + delta.y, width: ds.width, height: ds.height), keepSize: true)
                            } else {
                                crop = clamp(CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y)), keepSize: false)
                            }
                        }
                        .onEnded { _ in dragStart = nil }
                )
            }
            .padding(12)
            Divider()
            HStack(spacing: 10) {
                Text("\(Int(crop.width)) × \(Int(crop.height)) px")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("Drag to select. Drag inside to move. Drag a corner to resize.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { crop = CGRect(origin: .zero, size: pixelSize) }.disabled(isWhole)
                Button("Cancel") { onFinish(nil) }.keyboardShortcut(.cancelAction)
                Button("Crop and Save as New Clip") { onFinish(crop) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isWhole || crop.width < 1 || crop.height < 1)
            }
            .padding(10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func cropOverlay(fit: CGRect, scale: CGFloat) -> some View {
        let r = viewRect(crop, fit: fit, scale: scale)
        Rectangle()
            .strokeBorder(Color.white, lineWidth: 1.5)
            .frame(width: max(1, r.width), height: max(1, r.height))
            .offset(x: r.minX, y: r.minY)
            .shadow(color: .black.opacity(0.5), radius: 1)
            .allowsHitTesting(false)
        ForEach(Handle.allCases, id: \.self) { handle in
            let p = handle.point(in: r)
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.4)))
                .position(p)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStart == nil { dragStart = crop }
                            guard let ds = dragStart else { return }
                            let current = pixelPoint(value.location, fit: fit, scale: scale)
                            crop = clamp(handle.resize(ds, to: current), keepSize: false)
                        }
                        .onEnded { _ in dragStart = nil }
                )
        }
    }

    enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        func point(in r: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: r.minX, y: r.minY)
            case .top: return CGPoint(x: r.midX, y: r.minY)
            case .topRight: return CGPoint(x: r.maxX, y: r.minY)
            case .right: return CGPoint(x: r.maxX, y: r.midY)
            case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
            case .bottom: return CGPoint(x: r.midX, y: r.maxY)
            case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
            case .left: return CGPoint(x: r.minX, y: r.midY)
            }
        }

        func resize(_ r: CGRect, to p: CGPoint) -> CGRect {
            var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
            switch self {
            case .topLeft: minX = p.x; minY = p.y
            case .top: minY = p.y
            case .topRight: maxX = p.x; minY = p.y
            case .right: maxX = p.x
            case .bottomRight: maxX = p.x; maxY = p.y
            case .bottom: maxY = p.y
            case .bottomLeft: minX = p.x; maxY = p.y
            case .left: minX = p.x
            }
            return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
        }
    }

    private func fittedRect(in size: CGSize) -> CGRect {
        let scale = min(size.width / pixelSize.width, size.height / pixelSize.height, 1.0 * max(1, NSScreen.main?.backingScaleFactor ?? 2) / 1)
        let w = pixelSize.width * min(scale, size.width / pixelSize.width, size.height / pixelSize.height)
        let h = pixelSize.height * min(scale, size.width / pixelSize.width, size.height / pixelSize.height)
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func viewRect(_ r: CGRect, fit: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: fit.minX + r.minX * scale, y: fit.minY + r.minY * scale, width: r.width * scale, height: r.height * scale)
    }

    private func pixelPoint(_ p: CGPoint, fit: CGRect, scale: CGFloat) -> CGPoint {
        CGPoint(x: (p.x - fit.minX) / scale, y: (p.y - fit.minY) / scale)
    }

    private func clamp(_ r: CGRect, keepSize: Bool) -> CGRect {
        var out = r
        if keepSize {
            out.origin.x = max(0, min(out.origin.x, pixelSize.width - out.width))
            out.origin.y = max(0, min(out.origin.y, pixelSize.height - out.height))
        } else {
            let minX = max(0, out.minX), minY = max(0, out.minY)
            let maxX = min(pixelSize.width, out.maxX), maxY = min(pixelSize.height, out.maxY)
            out = CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        }
        return out.integral
    }
}
