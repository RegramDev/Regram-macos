import Cocoa

public enum PeerNameColorProvider {
    private static let lock = NSLock()
    private static var enabled = true
    private static var provider: ((NSColor) -> NSColor)?

    public static var isEnabled: Bool {
        lock.lock()
        let result = enabled
        lock.unlock()
        return result
    }

    public static func install(enabled: Bool = true, transform: ((NSColor) -> NSColor)? = nil) {
        lock.lock()
        self.enabled = enabled
        provider = transform
        lock.unlock()
    }

    public static func withOriginalColors<Result>(_ action: () throws -> Result) rethrows -> Result {
        let key = "ColorPalette.PeerNameColorProvider.Original"
        let previous = Thread.current.threadDictionary[key]
        Thread.current.threadDictionary[key] = true
        defer { Thread.current.threadDictionary[key] = previous }
        return try action()
    }

    static func color(_ original: NSColor) -> NSColor {
        if Thread.current.threadDictionary["ColorPalette.PeerNameColorProvider.Original"] as? Bool == true { return original }
        lock.lock()
        let transform = provider
        lock.unlock()
        return transform?(original) ?? original
    }
}
