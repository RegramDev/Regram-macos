import Cocoa
import TGUIKit
import RegramCore
import TelegramTheme

public enum RegramSettingsArtwork {
    private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 64
        return cache
    }()

    public static func entry(dark: Bool) -> CGImage? {
        cached("entry-\(dark)") {
            guard let image = resource("regram-" + (dark ? "dark" : "light"), extension: "png") else { return nil }
            return generateImage(CGSize(width: 24, height: 24), contextGenerator: { size, context in
                let bounds = CGRect(origin: .zero, size: size)
                context.clear(bounds)
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                context.addPath(CGPath(roundedRect: bounds, cornerWidth: 5, cornerHeight: 5, transform: nil))
                context.clip()
                context.interpolationQuality = .high
                context.draw(image.precomposed(), in: bounds)
            })
        }
    }

    static func category(_ category: RegramCategory) -> CGImage? {
        let symbol: String
        switch category {
        case .messages: symbol = "bubble.left.and.bubble.right"
        case .input: symbol = "keyboard"
        case .translation: symbol = "character.bubble"
        case .privacy: symbol = "hand.raised"
        case .media: symbol = "photo.on.rectangle"
        case .appearance: symbol = "paintpalette"
        case .network: symbol = "network"
        case .tools: symbol = "slider.horizontal.3"
        case .notifications: symbol = "bell"
        }
        return symbolImage(symbol)
    }

    static func symbolImage(_ name: String) -> CGImage? {
        cached("symbol-tile-\(name)-\(theme.colors.accent.hexString)") {
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 17, weight: .regular)) else { return nil }
            let glyph = image.precomposed(theme.colors.accent)
            let glyphSize = glyph.backingSize.aspectFitted(NSSize(width: 18, height: 18))
            return generateImage(NSSize(width: 24, height: 24), contextGenerator: { size, context in
                let bounds = CGRect(origin: .zero, size: size)
                context.clear(bounds)
                context.setFillColor(theme.colors.accent.withAlphaComponent(0.14).cgColor)
                context.addPath(CGPath(roundedRect: bounds, cornerWidth: 7, cornerHeight: 7, transform: nil))
                context.fillPath()
                context.draw(glyph, in: CGRect(x: (size.width - glyphSize.width) / 2, y: (size.height - glyphSize.height) / 2, width: glyphSize.width, height: glyphSize.height))
            })
        }
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
