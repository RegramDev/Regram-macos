import Cocoa
import Postbox
import TelegramCore
import RegramCore
import GalleryUI
import TGUIKit

@main
struct CapturePolicyChecks {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let accountId = Int64.min + 591
        let otherAccountId = accountId + 1
        defer {
            RegramPreferences.shared.removeAccount(accountId)
            RegramPreferences.shared.removeAccount(otherAccountId)
        }
        func message(_ namespace: PeerId.Namespace = Namespaces.Peer.CloudChannel, media: [Media], flags: MessageFlags = [.Incoming, .CopyProtected], attributes: [MessageAttribute] = []) -> Message {
            Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: PeerId(namespace: namespace, id: ._internalFromInt64Value(1)), namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 1, flags: flags, tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: "fixture", attributes: attributes, media: media, peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        }
        let image = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: 1), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        let protected = message(media: [image])
        let cached = CachedUserData().withUpdatedFlags(.copyProtectionEnabled)
        let privateProtected = message(Namespaces.Peer.CloudUser, media: [image], flags: [.Incoming])
        let sensitive = [
            message(Namespaces.Peer.SecretChat, media: [image]),
            message(media: [TelegramMediaExpiredContent(data: .image)]),
            message(media: [TelegramMediaPaidContent(amount: 1, extendedMedia: [.full(media: image)])]),
            message(media: [image], attributes: [RGRevokedMessageAttribute(date: 1, wasSecretMedia: true)])
        ]
        var assertions = 0
        func check(_ value: Bool, _ name: String) {
            assertions += 1
            precondition(value, name)
        }
        for mask in 0..<16 {
            RegramPreferences.shared.update(accountId: accountId) {
                $0["antiRevoke"] = .bool(mask & 1 != 0)
                $0["antiRevokeSkipBots"] = .bool(mask & 2 != 0)
                $0["quickTranslateButton"] = .bool(mask & 4 != 0)
                $0["ghostDontReadStories"] = .bool(mask & 8 != 0)
                $0["hideStories"] = .bool(mask & 8 != 0)
                $0["localPremium"] = .bool(mask & 4 != 0)
                $0["features.enablePanguOnReceiving"] = .bool(mask & 2 != 0)
            }
            for enabled in [false, true, false] {
                RegramPreferences.shared.update(accountId: accountId) { $0["allowSavingProtectedContent"] = .bool(enabled) }
                check(chatProtects(protected, accountId: accountId, cachedData: nil) == !enabled, "chat thumbnail follows the saved setting")
                check(chatProtects(protected, accountId: otherAccountId, cachedData: nil), "capture override stays within one account")
                check(chatProtects(privateProtected, accountId: accountId, cachedData: cached) == !enabled, "cached private-chat protection is respected")
                let entry = GalleryEntry.media(image, 0, protected)
                check(galleryProtects(entry, accountId: accountId, cachedPeerData: nil) == !enabled, "gallery window follows the saved setting")
                check(thumbProtects(entry, accountId: accountId) == !enabled, "gallery thumbnails follow the saved setting")
                for message in sensitive {
                    check(chatProtects(message, accountId: accountId, cachedData: nil), "sensitive media keeps chat protection")
                    check(galleryProtects(.media(image, 0, message), accountId: accountId, cachedPeerData: nil), "sensitive media keeps gallery protection")
                }
                let bitmap = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                bitmap.setFillColor(NSColor.systemBlue.cgColor)
                bitmap.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
                let view = TransformImageView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
                view.image = bitmap.makeImage()
                view.preventsCapture = chatProtects(protected, accountId: accountId, cachedData: nil)
                check((view.layer?.contents != nil) == enabled, "capture-approved image is on the normal AppKit layer")
            }
        }
        check(!galleryProtects(nil, accountId: accountId, cachedPeerData: nil), "empty gallery releases its capture exclusion")
        print("Capture policy: \(assertions) checks passed; isolated fixture preferences, no real messages or account changes")
    }
}
