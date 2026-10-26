import AppKit

enum RegramApplicationIconRenderer {
    static let canvasSize = 1024
    static let contentInset: CGFloat = 100.0 / 1024.0
    static let cornerRadiusRatio: CGFloat = 0.225
    static let representationSizes = [16, 32, 64, 128, 256, 512, 1024]

    static func render(_ source: CGImage, pixelSize: Int) -> CGImage? {
        guard (1...4096).contains(pixelSize), let context = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: pixelSize * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        let inset = CGFloat(pixelSize) * contentInset
        let frame = canvas.insetBy(dx: inset, dy: inset)
        let radius = frame.width * cornerRadiusRatio
        context.clear(canvas)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        context.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.draw(source, in: frame)
        return context.makeImage()
    }

    static func image(_ source: CGImage) -> NSImage? {
        let size = NSSize(width: canvasSize, height: canvasSize)
        let image = NSImage(size: size)
        for pixelSize in representationSizes {
            guard let rendered = render(source, pixelSize: pixelSize) else { return nil }
            let representation = NSBitmapImageRep(cgImage: rendered)
            representation.size = size
            image.addRepresentation(representation)
        }
        image.isTemplate = false
        return image
    }
}
