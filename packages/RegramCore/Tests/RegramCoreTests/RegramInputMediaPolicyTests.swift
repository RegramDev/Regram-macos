import XCTest
@testable import RegramCore

final class RegramInputMediaPolicyTests: XCTestCase {
    func testAutomaticInlineBotQueriesOnlyStandaloneMatchingLinks() {
        XCTAssertNil(RGAutomaticInlineBots.match("https://x.com/user/status/12", enabled: false))
        XCTAssertEqual(RGAutomaticInlineBots.match(" https://x.com/user/status/12?x=1 ", enabled: true)?.query, "https://x.com/user/status/12?x=1")
        XCTAssertEqual(RGAutomaticInlineBots.match("https://www.pixiv.net/en/artworks/123", enabled: true)?.username, "Pixiv_bot")
        for value in ["Look https://x.com/user/status/12", "https://x.com/user/status/12 more", "https://x.com.evil/user/status/12", "https://user:pass@x.com/user/status/12", "https://x.com:443/user/status/12", "https://github.com/user/repo.git", "https://x.com/user/status/12\nhttps://x.com/user/status/13"] {
            XCTAssertNil(RGAutomaticInlineBots.match(value, enabled: true), value)
        }
    }

    func testAutomaticInlineBotDismissalKeepsDraftAndAccountScope() {
        let dismissals = RGAutomaticInlineBotDismissals()
        let text = "https://x.com/user/status/12"
        dismissals.dismiss(text, accountId: 1, peerId: 2, threadId: 3)
        XCTAssertFalse(dismissals.permits(text, accountId: 1, peerId: 2, threadId: 3))
        XCTAssertTrue(dismissals.permits(text, accountId: 2, peerId: 2, threadId: 3))
        XCTAssertTrue(dismissals.permits(text, accountId: 1, peerId: 2, threadId: 4))
        XCTAssertTrue(dismissals.permits(text + "?x=1", accountId: 1, peerId: 2, threadId: 3))
        XCTAssertTrue(dismissals.permits(text, accountId: 1, peerId: 2, threadId: 3))
    }

    func testMediaPolicyRetainsNativeResolutionAndUsesBoundedPreferences() {
        var settings = RegramAccountSettings()
        settings["outgoingPhotoQuality"] = .integer(72)
        settings["sendLargePhotos"] = .bool(true)
        settings["recentStickerLimit"] = .integer(150)
        settings["stickerSize"] = .integer(84)
        XCTAssertEqual(RGMediaPolicy.photoQuality(settings: settings), 0.72)
        XCTAssertEqual(RGMediaPolicy.photoQuality(settings: settings, pasted: true), 1.0)
        XCTAssertEqual(RGMediaPolicy.photoMaximumDimension(native: 1280, settings: settings), 2560)
        XCTAssertEqual(RGMediaPolicy.photoMaximumDimension(native: 4096, settings: settings), 4096)
        settings["sendLargePhotos"] = .bool(false)
        XCTAssertEqual(RGMediaPolicy.photoMaximumDimension(native: 1280, settings: settings, pasted: true), 2560)
        XCTAssertEqual(RGMediaPolicy.recentStickerLimit(settings: settings), 150)
        XCTAssertEqual(RGMediaPolicy.stickerScale(settings: settings), 0.84)
        settings["outgoingPhotoQuality"] = .integer(0)
        settings["stickerSize"] = .integer(0)
        XCTAssertEqual(RGMediaPolicy.photoQuality(settings: settings), 0)
        XCTAssertEqual(RGMediaPolicy.stickerScale(settings: settings), 0)
        XCTAssertEqual(RGMediaPolicy.photoQuality(settings: settings, pasted: true), 1)
        settings.values["stickerSize"] = .integer(200)
        XCTAssertEqual(RGMediaPolicy.stickerScale(settings: settings), 2)
        settings.values["recentStickerLimit"] = .integer(1000)
        XCTAssertEqual(RGMediaPolicy.recentStickerLimit(settings: settings), 20)
    }

    func testDoubleClickOverrideOnlyAffectsMessagesWithoutEditPermission() {
        var settings = RegramAccountSettings()
        XCTAssertEqual(RGMessageDoubleClickAction.resolved(settings: settings, canEdit: true), .sendReaction)
        XCTAssertFalse(RGMessageDoubleClickAction.allCases.map(\.rawValue).contains("native"))
        settings["messageDoubleTapAction"] = .string("edit")
        settings.values["messageDoubleTapActionWithoutEditPermission"] = .string("reply")
        XCTAssertEqual(RGMessageDoubleClickAction.resolved(settings: settings, canEdit: true), .edit)
        XCTAssertEqual(RGMessageDoubleClickAction.resolved(settings: settings, canEdit: false), .reply)
        settings.values["messageDoubleTapActionWithoutEditPermission"] = .string("sameAsUnified")
        XCTAssertEqual(RGMessageDoubleClickAction.resolved(settings: settings, canEdit: false), .sendReaction)
    }
}
