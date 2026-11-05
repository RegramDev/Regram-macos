import Cocoa
import Postbox
import TelegramCore
import RegramCore

enum ExpiryUpdate {
    case skip
    case update(StoreMessage)
}

final class ExpiryTransaction {
    let message: Message
    var updated: StoreMessage?

    init(_ message: Message) { self.message = message }

    func updateMessage(_ id: MessageId, update: (Message) -> ExpiryUpdate) {
        precondition(id == message.id)
        if case let .update(value) = update(message) { updated = value }
    }
}

@main
struct MessageExpiryChecks {
    static var assertions = 0

    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        assertions += 1
        if !condition() { fatalError(label) }
    }

    static func message(_ attributes: [MessageAttribute], secret: Bool = false, media: [Media] = []) -> Message {
        Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: PeerId(namespace: secret ? Namespaces.Peer.SecretChat : Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(10)), namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 1, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: "retained caption", attributes: attributes, media: media, peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    static func main() {
        let autoremove = AutoremoveTimeoutMessageAttribute(timeout: 86400, countdownBeginTime: 1)
        let autoclear = AutoclearTimeoutMessageAttribute(timeout: viewOnceTimeout, countdownBeginTime: 2)
        let source = message([autoremove, autoclear])
        for tag: UInt16 in [0, 1] {
            let transaction = ExpiryTransaction(source)
            rgIgnoreMessageExpiry(transaction: transaction, id: source.id, tag: tag)
            guard let updated = transaction.updated else { fatalError("missing expiry update") }
            check(updated.text == source.text, "expiry preserves message text")
            check(updated.attributes.count == 2, "expiry preserves both timeout attributes")
            check(!updated.attributes.contains { $0 is RGRevokedMessageAttribute }, "ignoring a timer never creates a revoked marker")
            let remove = updated.attributes.compactMap { $0 as? AutoremoveTimeoutMessageAttribute }.first!
            let clear = updated.attributes.compactMap { $0 as? AutoclearTimeoutMessageAttribute }.first!
            check(remove.countdownBeginTime == 1 && clear.countdownBeginTime == 2, "paused timers cannot be restarted as unread")
            check(remove.timeout == 86400 && clear.timeout == viewOnceTimeout, "timeouts retain their content semantics")
            check(remove.rgCountdownPaused == (tag == 0), "only the requested removal timer is stopped")
            check(clear.rgCountdownPaused == (tag == 1), "only the requested clearing timer is stopped")
            check((remove.automaticTimestampBasedAttribute == nil) == (tag == 0), "removal timestamp does not restart")
            check((clear.automaticTimestampBasedAttribute == nil) == (tag == 1), "clearing timestamp does not restart")
            let removeEncoder = PostboxEncoder()
            remove.encode(removeEncoder)
            let decodedRemove = AutoremoveTimeoutMessageAttribute(decoder: PostboxDecoder(buffer: MemoryBuffer(data: removeEncoder.makeData())))
            check(decodedRemove.countdownBeginTime == remove.countdownBeginTime, "removal start time survives serialization")
            check(decodedRemove.rgCountdownPaused == remove.rgCountdownPaused, "removal pause persists across restart")
            let clearEncoder = PostboxEncoder()
            clear.encode(clearEncoder)
            let decodedClear = AutoclearTimeoutMessageAttribute(decoder: PostboxDecoder(buffer: MemoryBuffer(data: clearEncoder.makeData())))
            check(decodedClear.countdownBeginTime == clear.countdownBeginTime, "clearing start time survives serialization")
            check(decodedClear.rgCountdownPaused == clear.rgCountdownPaused, "clearing pause persists across restart")
        }
        let alreadyStopped = message([AutoremoveTimeoutMessageAttribute(timeout: 10, countdownBeginTime: 1, rgCountdownPaused: true)])
        let stopped = ExpiryTransaction(alreadyStopped)
        rgIgnoreMessageExpiry(transaction: stopped, id: alreadyStopped.id, tag: 0)
        check(stopped.updated == nil, "already stopped timers skip redundant updates")

        let image = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 1), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        let protected = message([AutoclearTimeoutMessageAttribute(timeout: viewOnceTimeout, countdownBeginTime: 1, rgCountdownPaused: true)], media: [image])
        check(protected.containsSecretMedia, "stopping a self-destruct timer preserves media protection")

        for mask in 0..<8 {
            var settings = RegramAccountSettings()
            settings["antiRevoke"] = .bool(mask & 1 != 0)
            settings["antiAutoDelete"] = .bool(mask & 2 != 0)
            settings["antiSelfDestruct"] = .bool(mask & 4 != 0)
            check(ignoresExpiry(source, isRemove: true, settings: settings) == (mask & 2 != 0), "auto-delete timer is independent")
            check(ignoresExpiry(source, isRemove: false, settings: settings) == (mask & 4 != 0), "cloud self-destruct timer is independent")
            check(ignoresExpiry(message([], secret: true), isRemove: true, settings: settings) == (mask & 4 != 0), "secret chat timer is independent")
            check(settings.shouldRetainRevokedMessage(peerId: source.id.peerId.toInt64(), authorIsBot: false) == (mask & 1 != 0), "server revocation requires explicit retention")
            for dim in [false, true] {
                settings["revokedMarkerDimMessages"] = .bool(dim)
                check(revokedOpacity(source, regramSettings: settings) == 1, "normal messages stay opaque")
                let revoked = message([RGRevokedMessageAttribute(date: 1)])
                check(revokedOpacity(revoked, regramSettings: settings) == (mask & 1 != 0 && dim ? 0.5 : 1), "opacity requires both retention and dimming")
            }
        }
        print("Message expiry and opacity: \(assertions) checks passed")
    }
}
