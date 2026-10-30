import AppKit
import Foundation
import SwiftSignalKit

public enum RegramBranding {
    public static let didChange = Notification.Name("Regram.NativeAppIcon.DidChange")
    public static let icons = ["RGConversation", "RGAzure", "RGIris", "RGMint", "RGGathering", "RGAmber", "RGNebula", "RGJade", "RGSilver", "RGClassic"]
    private static let iconKey = "RegramNativeApplicationIcon"
    private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 4
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    public static var selectedIcon: String {
        let value = UserDefaults.standard.string(forKey: iconKey) ?? "RGConversation"
        return icons.contains(value) ? value : "RGConversation"
    }

    public static var selection: Signal<String, NoError> {
        Signal { subscriber in
            let observer = NotificationCenter.default.addObserver(forName: didChange, object: nil, queue: .main) { _ in subscriber.putNext(selectedIcon) }
            subscriber.putNext(selectedIcon)
            return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
        } |> distinctUntilChanged
    }

    public static func titleKey(_ name: String) -> String {
        let names = ["RGConversation": "conversation", "RGAzure": "azure", "RGIris": "iris", "RGMint": "mint", "RGGathering": "gathering", "RGAmber": "amber", "RGNebula": "nebula", "RGJade": "jade", "RGClassic": "classic", "RGSilver": "silver"]
        return "AppIcon.Name." + (names[name] ?? "conversation")
    }

    public static func image(_ name: String, dark: Bool) -> NSImage? {
        guard icons.contains(name) else { return nil }
        let filename = name == "RGSilver" ? name : name + (dark ? "-dark" : "-light")
        let suffix = name == "RGSilver" ? "jpg" : "png"
        guard let url = Bundle.module.url(forResource: filename, withExtension: suffix, subdirectory: "Branding") ?? Bundle.module.url(forResource: filename, withExtension: suffix) else { return nil }
        return NSImage(contentsOf: url)
    }

    public static func renderedIcon(_ name: String, dark: Bool, pixelSize: Int) -> CGImage? {
        guard let image = image(name, dark: dark), let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return RegramApplicationIconRenderer.render(source, pixelSize: pixelSize)
    }

    public static func applicationIcon(_ name: String, dark: Bool) -> NSImage? {
        let key = (name + (dark ? ":dark" : ":light")) as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        guard let image = image(name, dark: dark), let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let rendered = RegramApplicationIconRenderer.image(source) else { return nil }
        iconCache.setObject(rendered, forKey: key, cost: 6 * 1024 * 1024)
        return rendered
    }

    public static func effectImage(lightning: Bool) -> NSImage? {
        let name = lightning ? "RGLightning" : "RGSnowflake"
        let ext = lightning ? "pdf" : "png"
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Branding") ?? Bundle.module.url(forResource: name, withExtension: ext) else { return nil }
        return NSImage(contentsOf: url)
    }

    @discardableResult public static func selectIcon(_ name: String, dark: Bool) -> Bool {
        precondition(Thread.isMainThread)
        guard let image = applicationIcon(name, dark: dark) else { return false }
        NSApplication.shared.applicationIconImage = image
        UserDefaults.standard.set(name, forKey: iconKey)
        NotificationCenter.default.post(name: didChange, object: nil)
        return true
    }

    public static func applyCurrentIcon(dark: Bool) {
        precondition(Thread.isMainThread)
        if let image = applicationIcon(selectedIcon, dark: dark) { NSApplication.shared.applicationIconImage = image }
    }
}
