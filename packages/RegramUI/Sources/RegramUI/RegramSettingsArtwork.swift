import Cocoa
import TGUIKit
import RegramCore
import TelegramTheme

public enum RegramSettingsArtwork {
    private static let cache = NSCache<NSString, CGImage>()

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
        switch category {
        case .messages: return theme.icons.settingsFilters
        case .input: return theme.icons.settingsGeneral
        case .translation: return theme.icons.settingsLanguage
        case .privacy: return theme.icons.settingsSecurity
        case .media: return theme.icons.settingsStorage
        case .appearance: return theme.icons.settingsAppearance
        case .network: return theme.icons.settingsProxy
        case .tools: return theme.icons.settingsSessions
        case .notifications: return theme.icons.settingsNotifications
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
