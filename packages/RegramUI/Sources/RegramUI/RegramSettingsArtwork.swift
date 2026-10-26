import Cocoa
import TGUIKit
import RegramCore

public enum RegramSettingsArtwork {
    private static let cache = NSCache<NSString, CGImage>()

    public static func entry(dark: Bool) -> CGImage? {
        cached("entry-\(dark)") {
            guard let image = resource("regram-" + (dark ? "dark" : "light"), extension: "png") else { return nil }
            return generateImage(CGSize(width: 30, height: 30), contextGenerator: { size, context in
                let bounds = CGRect(origin: .zero, size: size)
                context.clear(bounds)
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                context.addPath(CGPath(roundedRect: bounds, cornerWidth: 7, cornerHeight: 7, transform: nil))
                context.clip()
                context.interpolationQuality = .high
                context.draw(image.precomposed(), in: bounds)
            })
        }
    }

    static func category(_ category: RegramCategory) -> CGImage? {
        cached(category.rawValue) {
            guard let glyph = resource("category-" + category.rawValue, extension: "pdf") else { return nil }
            let colors: [RegramCategory: UInt32] = [
                .messages: 0x5E5CE6, .input: 0x0079FF, .translation: 0xAF52DE,
                .privacy: 0x8E8E93, .media: 0xFF9F0A, .appearance: 0x32ADE6,
                .network: 0x34C759, .tools: 0xFF9F0A
            ]
            return generateImage(CGSize(width: 30, height: 30), contextGenerator: { size, context in
                let bounds = CGRect(origin: .zero, size: size)
                context.clear(bounds)
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                context.addPath(CGPath(roundedRect: bounds, cornerWidth: 8, cornerHeight: 8, transform: nil))
                context.clip()
                context.setFillColor(NSColor(rgb: colors[category] ?? 0).cgColor)
                context.fill(bounds)
                if let gradient = resource("category-gradient", extension: "pdf") {
                    context.setBlendMode(.plusLighter)
                    context.draw(gradient.precomposed(), in: bounds)
                }
                if let backdrop = resource("category-backdrop", extension: "png") {
                    context.setBlendMode(.overlay)
                    context.draw(backdrop.precomposed(), in: bounds)
                }
                context.setBlendMode(.normal)
                let rect = CGRect(x: (size.width - glyph.size.width) / 2, y: (size.height - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height)
                context.clip(to: rect, mask: glyph.precomposed())
                context.setFillColor(NSColor.white.cgColor)
                context.fill(rect)
            })
        }
    }

    static func editor(_ name: String, color: NSColor) -> CGImage? {
        cached("editor-\(name)-\(color.hexString)") {
            guard #available(macOS 11.0, *), let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 18, weight: .semibold)), let glyph = trimmedGlyph(image.precomposed(.white)) else { return nil }
            return generateImage(CGSize(width: 30, height: 30), contextGenerator: { size, context in
                let bounds = CGRect(origin: .zero, size: size)
                context.clear(bounds)
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                context.addPath(CGPath(roundedRect: bounds, cornerWidth: 7, cornerHeight: 7, transform: nil))
                context.setFillColor(color.cgColor)
                context.fillPath()
                let scale = 18 / CGFloat(max(glyph.width, glyph.height))
                let imageSize = CGSize(width: CGFloat(glyph.width) * scale, height: CGFloat(glyph.height) * scale)
                context.draw(glyph, in: CGRect(x: (size.width - imageSize.width) / 2, y: (size.height - imageSize.height) / 2, width: imageSize.width, height: imageSize.height))
            })
        }
    }

    private static func trimmedGlyph(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue), let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0 ..< image.height {
            for x in 0 ..< image.width where pixels[y * context.bytesPerRow + x * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return image.cropping(to: CGRect(x: CGFloat(minX), y: CGFloat(minY), width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1)))
    }

    private static func resource(_ name: String, extension suffix: String) -> NSImage? {
        Bundle.module.url(forResource: name, withExtension: suffix).flatMap(NSImage.init(contentsOf:))
    }

    private static func cached(_ key: String, make: () -> CGImage?) -> CGImage? {
        let key = "\(key)-\(System.backingScale)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let image = make() else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
