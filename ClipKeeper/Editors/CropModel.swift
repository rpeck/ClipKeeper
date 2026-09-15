import Foundation

/// The crop rectangle and the rules for drawing, moving, and resizing it.
/// Pure logic, so the tests cover it without a window. Coordinates are image
/// pixels with the origin at the top-left.
struct CropModel: Equatable {
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
    }

    /// What a drag that starts on the image does.
    enum DragMode: Equatable {
        case draw(origin: CGPoint)
        case move(original: CGRect, grab: CGPoint)
    }

    let imageSize: CGSize
    private(set) var rect: CGRect

    init(imageSize: CGSize) {
        self.imageSize = imageSize
        rect = CGRect(origin: .zero, size: imageSize)
    }

    var whole: CGRect { CGRect(origin: .zero, size: imageSize) }

    /// True when nothing is cropped away.
    var isWhole: Bool { rect.integral == whole.integral }

    var canCrop: Bool { !isWhole && rect.width >= 1 && rect.height >= 1 }

    mutating func reset() { rect = whole }

    /// A drag on a whole, uncropped image draws a new rectangle. A drag that
    /// starts inside a partial rectangle moves it. A drag outside draws.
    func dragMode(at point: CGPoint) -> DragMode {
        if !isWhole, rect.contains(point) {
            return .move(original: rect, grab: point)
        }
        return .draw(origin: clampPoint(point))
    }

    mutating func drag(_ mode: DragMode, to point: CGPoint) {
        switch mode {
        case .draw(let origin):
            let p = clampPoint(point)
            rect = clamp(CGRect(x: min(origin.x, p.x), y: min(origin.y, p.y), width: abs(p.x - origin.x), height: abs(p.y - origin.y)), keepSize: false)
        case .move(let original, let grab):
            let moved = original.offsetBy(dx: point.x - grab.x, dy: point.y - grab.y)
            rect = clamp(moved, keepSize: true)
        }
    }

    /// Moves one handle of `original` to `point`. The opposite side stays.
    mutating func resize(_ handle: Handle, from original: CGRect, to point: CGPoint) {
        let p = clampPoint(point)
        var minX = original.minX, minY = original.minY, maxX = original.maxX, maxY = original.maxY
        switch handle {
        case .topLeft: minX = p.x; minY = p.y
        case .top: minY = p.y
        case .topRight: maxX = p.x; minY = p.y
        case .right: maxX = p.x
        case .bottomRight: maxX = p.x; maxY = p.y
        case .bottom: maxY = p.y
        case .bottomLeft: minX = p.x; maxY = p.y
        case .left: minX = p.x
        }
        rect = clamp(CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY)), keepSize: false)
    }

    private func clampPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: max(0, min(imageSize.width, p.x)), y: max(0, min(imageSize.height, p.y)))
    }

    private func clamp(_ r: CGRect, keepSize: Bool) -> CGRect {
        var out = r
        if keepSize {
            out.size.width = min(out.width, imageSize.width)
            out.size.height = min(out.height, imageSize.height)
            out.origin.x = max(0, min(out.origin.x, imageSize.width - out.width))
            out.origin.y = max(0, min(out.origin.y, imageSize.height - out.height))
        } else {
            let minX = max(0, out.minX), minY = max(0, out.minY)
            let maxX = min(imageSize.width, out.maxX), maxY = min(imageSize.height, out.maxY)
            out = CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        }
        return out.integral
    }
}
