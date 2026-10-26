import AppKit
import SwiftSignalKit

public enum InterfaceFontProvider {
    public typealias Provider = (CGFloat, NSFont.Weight, Bool) -> NSFont?
    private static let lock = NSLock()
    private static var provider: Provider?
    private static var revision: Int64 = 0
    private static let revisionPromise = ValuePromise<Int64>(0, ignoreRepeated: true)
    public static var changes: Signal<Int64, NoError> { revisionPromise.get() }

    public static func install(_ provider: Provider?) {
        lock.lock()
        self.provider = provider
        lock.unlock()
        invalidate()
    }

    public static func invalidate() {
        lock.lock()
        revision &+= 1
        let value = revision
        lock.unlock()
        revisionPromise.set(value)
    }

    public static func withNativeFonts<Result>(_ action: () throws -> Result) rethrows -> Result {
        let key = "TGUIKit.InterfaceFontProvider.NativeFonts"
        let previous = Thread.current.threadDictionary[key]
        Thread.current.threadDictionary[key] = true
        defer { Thread.current.threadDictionary[key] = previous }
        return try action()
    }

    static func font(size: CGFloat, weight: NSFont.Weight, italic: Bool = false) -> NSFont? {
        if Thread.current.threadDictionary["TGUIKit.InterfaceFontProvider.NativeFonts"] as? Bool == true { return nil }
        lock.lock()
        let provider = self.provider
        lock.unlock()
        return provider?(size, weight, italic)
    }
}
