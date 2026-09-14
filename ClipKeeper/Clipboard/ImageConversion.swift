import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image format conversion and sizing helpers.
enum ImageConversion {
    enum Format: String, CaseIterable, Identifiable {
        case png, jpeg, tiff, heic, gif

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .png: return "PNG"
            case .jpeg: return "JPEG"
            case .tiff: return "TIFF"
            case .heic: return "HEIC"
            case .gif: return "GIF"
            }
        }
        var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
        var utType: UTType {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            case .tiff: return .tiff
            case .heic: return .heic
            case .gif: return .gif
            }
        }
        var pasteboardType: String {
            switch self {
            case .png: return PBType.png
            case .jpeg: return PBType.jpeg
            case .tiff: return PBType.tiff
            case .heic: return PBType.heic
            case .gif: return PBType.gif
            }
        }

        static func from(pasteboardType: String) -> Format? {
            allCases.first { $0.pasteboardType == pasteboardType }
        }
    }

    /// Pixel size read from the image header, without decoding the full image.
    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Encodes a CGImage in the given format.
    static func data(from cgImage: CGImage, format: Format, quality: Double = 0.9) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, format.utType.identifier as CFString, 1, nil) else { return nil }
        var options: [CFString: Any] = [:]
        if format == .jpeg || format == .heic { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Converts image data from any readable format to the target format.
    static func convert(_ data: Data, to format: Format) -> Data? {
        guard let cg = cgImage(from: data) else { return nil }
        return self.data(from: cg, format: format)
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let cg = cgImage(from: image) else { return nil }
        return data(from: cg, format: .png)
    }

    /// Returns a PNG no larger than `maxDimension` on either side.
    static func downscaledPNG(_ image: NSImage, maxDimension: CGFloat) -> Data? {
        guard let cg = cgImage(from: image) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxDimension / max(w, h))
        if scale >= 1 { return data(from: cg, format: .png) }
        let newW = Int(w * scale), newH = Int(h * scale)
        guard let ctx = CGContext(data: nil, width: newW, height: newH, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let scaled = ctx.makeImage() else { return nil }
        return data(from: scaled, format: .png)
    }

    /// Crops to a rect in pixel coordinates with origin at the top-left.
    static func crop(_ data: Data, to rect: CGRect) -> Data? {
        guard let cg = cgImage(from: data) else { return nil }
        let bounded = rect.integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard bounded.width >= 1, bounded.height >= 1, let cropped = cg.cropping(to: bounded) else { return nil }
        return self.data(from: cropped, format: .png)
    }
}
