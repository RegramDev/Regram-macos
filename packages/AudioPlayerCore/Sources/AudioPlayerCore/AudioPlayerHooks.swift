import Foundation
import Postbox
import SwiftSignalKit

public struct AudioPlayerHooks {
    public let shouldIncludeMessage: ((Message, Int64) -> Bool)?
    public let messageVisibilityChanges: ((Int64) -> Signal<Void, NoError>)?

    public init(shouldIncludeMessage: ((Message, Int64) -> Bool)? = nil, messageVisibilityChanges: ((Int64) -> Signal<Void, NoError>)? = nil) {
        self.shouldIncludeMessage = shouldIncludeMessage
        self.messageVisibilityChanges = messageVisibilityChanges
    }

    private static let lock = NSLock()
    private static var installed = AudioPlayerHooks()

    public static var shared: AudioPlayerHooks {
        lock.lock()
        let hooks = installed
        lock.unlock()
        return hooks
    }

    public static func install(_ hooks: AudioPlayerHooks) {
        lock.lock()
        installed = hooks
        lock.unlock()
    }
}
