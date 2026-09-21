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

    @State private var model: CropModel
    @State private var dragMode: CropModel.DragMode?
    @State private var handleOrigin: CGRect?

    init(image: NSImage, pixelSize: CGSize, onFinish: @escaping (CGRect?) -> Void) {
        self.image = image
        self.pixelSize = pixelSize
        self.onFinish = onFinish
        _model = State(initialValue: CropModel(imageSize: pixelSize))
    }

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
                        p.addRect(viewRect(model.rect, fit: fit, scale: scale))
                    }
                    .fill(Color.black.opacity(model.isWhole ? 0 : 0.45), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    cropOverlay(fit: fit, scale: scale)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let current = pixelPoint(value.location, fit: fit, scale: scale)
                            if dragMode == nil {
                                dragMode = model.dragMode(at: pixelPoint(value.startLocation, fit: fit, scale: scale))
                            }
                            if let mode = dragMode { model.drag(mode, to: current) }
                        }
                        .onEnded { _ in dragMode = nil }
                )
            }
            .padding(12)
            Divider()
            HStack(spacing: 10) {
                Text("\(Int(model.rect.width)) × \(Int(model.rect.height)) px")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(model.isWhole ? "Drag on the image to choose the area to keep." : "Drag inside the area to move it. Drag a handle to resize it. Drag outside to start over.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { model.reset() }.disabled(model.isWhole)
                Button("Cancel") { onFinish(nil) }.keyboardShortcut(.cancelAction)
                Button("Crop and Save as New Clip") { onFinish(model.rect) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canCrop)
            }
            .padding(10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func cropOverlay(fit: CGRect, scale: CGFloat) -> some View {
        let r = viewRect(model.rect, fit: fit, scale: scale)
        Rectangle()
            .strokeBorder(Color.white, lineWidth: 1.5)
            .frame(width: max(1, r.width), height: max(1, r.height))
            .offset(x: r.minX, y: r.minY)
            .shadow(color: .black.opacity(0.5), radius: 1)
            .allowsHitTesting(false)
        ForEach(CropModel.Handle.allCases, id: \.self) { handle in
            let p = handle.point(in: r)
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.4)))
                .contentShape(Circle().inset(by: -6))
                .position(p)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if handleOrigin == nil { handleOrigin = model.rect }
                            guard let origin = handleOrigin else { return }
                            model.resize(handle, from: origin, to: pixelPoint(value.location, fit: fit, scale: scale))
                        }
                        .onEnded { _ in handleOrigin = nil }
                )
        }
    }

    private func fittedRect(in size: CGSize) -> CGRect {
        let scale = min(size.width / pixelSize.width, size.height / pixelSize.height)
        let w = pixelSize.width * scale, h = pixelSize.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func viewRect(_ r: CGRect, fit: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: fit.minX + r.minX * scale, y: fit.minY + r.minY * scale, width: r.width * scale, height: r.height * scale)
    }

    private func pixelPoint(_ p: CGPoint, fit: CGRect, scale: CGFloat) -> CGPoint {
        CGPoint(x: (p.x - fit.minX) / scale, y: (p.y - fit.minY) / scale)
    }
}
