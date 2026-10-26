import XCTest
import Postbox
import TelegramCore
@testable import ChatHistoryModel

final class RegramExportPolicyTests: XCTestCase {
    private let accountId = Int64.min + 325

    private func message(peerId: PeerId, media: [Media], attributes: [MessageAttribute] = [], flags: MessageFlags = [.Incoming]) -> Message {
        Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 1, flags: flags, tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: "caption", attributes: attributes, media: media, peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    func testGalleryExportRejectsSecretExpiredAndPaidMessages() {
        let user = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
        let secret = PeerId(namespace: Namespaces.Peer.SecretChat, id: ._internalFromInt64Value(1))
        let image = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: 1), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        XCTAssertFalse(regramCanSaveMessage(message(peerId: secret, media: [image]), accountId: accountId))
        XCTAssertFalse(regramCanSaveMessage(message(peerId: user, media: [TelegramMediaExpiredContent(data: .image)]), accountId: accountId))
        XCTAssertFalse(regramCanSaveMessage(message(peerId: user, media: [TelegramMediaPaidContent(amount: 1, extendedMedia: [.full(media: image)])]), accountId: accountId))
        XCTAssertTrue(regramCanSaveMessage(message(peerId: user, media: [image]), accountId: accountId))
        XCTAssertFalse(regramCanSaveMessage(message(peerId: user, media: [image]), accountId: accountId, cachedData: CachedUserData().withUpdatedFlags(.copyProtectionEnabled)))
        XCTAssertFalse(regramCanSaveMessage(message(peerId: user, media: [image]), accountId: accountId, cachedData: CachedUserData().withUpdatedFlags(.myCopyProtectionEnabled)))
        XCTAssertFalse(regramCanSaveMessage(message(peerId: user, media: [image], flags: [.Incoming, .CopyProtected]), accountId: accountId))
        XCTAssertFalse(regramCanSaveMessage(message(peerId: user, media: [image], attributes: [RGRevokedMessageAttribute(date: 1, wasSecretMedia: true)]), accountId: accountId))
        XCTAssertFalse(regramCanSaveMessage(message(peerId: user, media: [image], attributes: [RGRevokedMessageAttribute(date: 1, wasSecretMedia: nil)]), accountId: accountId))
    }

    func testFullChatNativeRoutingProtectsPaidSecretAndRetainedMedia() {
        let user = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
        let secret = PeerId(namespace: Namespaces.Peer.SecretChat, id: ._internalFromInt64Value(1))
        let image = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: 1), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        XCTAssertFalse(regramUsesNativeTranslation(message(peerId: user, media: [image])))
        XCTAssertTrue(regramUsesNativeTranslation(message(peerId: user, media: [TelegramMediaPaidContent(amount: 1, extendedMedia: [.full(media: image)])])))
        XCTAssertTrue(regramUsesNativeTranslation(message(peerId: secret, media: [image])))
        XCTAssertTrue(regramUsesNativeTranslation(message(peerId: user, media: [image], flags: [.Incoming, .CopyProtected])))
        XCTAssertTrue(regramUsesNativeTranslation(message(peerId: user, media: [image], attributes: [RGRevokedMessageAttribute(date: 1, wasSecretMedia: true)])))
        XCTAssertTrue(regramUsesNativeTranslation(message(peerId: user, media: [image], attributes: [RGRevokedMessageAttribute(date: 1, wasSecretMedia: nil)])))
    }

    func testBookmarkCloudFetchRejectsEveryNonRegularMessageNamespace() {
        let nonCloud = Set(Namespaces.Message.allLocal + [Namespaces.Message.ScheduledCloud, Namespaces.Message.QuickReplyCloud, Namespaces.Message.WelcomeMessageCloud, Int32.max])
        for peerNamespace in [Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel] {
            let peer = PeerId(namespace: peerNamespace, id: ._internalFromInt64Value(1))
            XCTAssertTrue(regramBookmarkCanFetchFromCloud(MessageId(peerId: peer, namespace: Namespaces.Message.Cloud, id: 1)))
            for namespace in nonCloud {
                XCTAssertFalse(regramBookmarkCanFetchFromCloud(MessageId(peerId: peer, namespace: namespace, id: 1)))
            }
        }
        let secret = PeerId(namespace: Namespaces.Peer.SecretChat, id: ._internalFromInt64Value(1))
        XCTAssertFalse(regramBookmarkCanFetchFromCloud(MessageId(peerId: secret, namespace: Namespaces.Message.Cloud, id: 1)))
    }
}
