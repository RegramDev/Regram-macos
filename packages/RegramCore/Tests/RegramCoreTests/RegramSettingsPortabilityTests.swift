import XCTest
@testable import RegramCore

final class RegramSettingsPortabilityTests: XCTestCase {
    func testSourceSearchFollowsMovedControlsAndRejectsRetiredLinks() throws {
        let composer = try XCTUnwrap(RegramSettingsRoute(page: "pro.messages", item: "mentionAsUserIdLink"))
        XCTAssertEqual(composer.destination, "pro.input/mentionAsUserIdLink")
        let camera = try XCTUnwrap(RegramSettingsRoute(page: "settings.media", item: "disableGalleryCamera"))
        XCTAssertEqual(camera.destination, "settings.recording/disableGalleryCamera")
        XCTAssertEqual(RegramSettingsRoute(page: "settings.app", item: "enableVoipTcp")?.destination, "settings.transfer/enableVoipTcp")
        XCTAssertEqual(RegramSettingsRoute(page: "antiFeatures", item: "revokedMarker")?.destination, "revokedMarker/revokedMarker")
        XCTAssertEqual(RegramSettingsRoute(page: "startupFolder")?.destination, "settings.folders/startupFolder")
        XCTAssertNil(RegramSettingsRoute(page: "settings.messageActions", item: "chatToolsEnabled"))
        XCTAssertNil(RegramSettingsRoute(page: "settings.chatList", item: "openArchiveOnPull"))
        XCTAssertNil(RegramSettingsRoute(page: "fonts", item: "../eraseAllData"))
        XCTAssertNil(RegramSettingsRoute(page: "textStyleMenu"))
        for item in ["inputToolbar", "textStyleMenu", "features.textStyleMenu.position", "disableSwipeToRecordStory", "disableGalleryCameraPreview", "startTelescopeWithRearCam", "disableSnapDeletionEffect", "forceSystemSharing", "antiScreenshotNotification", "accountColorsSaturation", "videoPIPSwipeDirection", "features.videoPIPSwipeDirection", "disableScrollToNextChannel", "disableScrollToNextTopic", "appIcons"] {
            XCTAssertNil(RegramSettingsRoute(page: "pro.input", item: item))
            XCTAssertFalse(RegramSettingsCatalog.sourceEntries.contains { $0.key == item })
        }
        XCTAssertEqual(RegramSettingsRoute(url: camera.url), camera)
        XCTAssertEqual(RegramSettingsRoute(page: "pro.tools", item: "localPremium")?.destination, "localGifts/localPremium")
        XCTAssertEqual(RegramSettingsRoute(page: "pro.home", item: "localGifts")?.destination, "localGifts")
        XCTAssertEqual(RegramSettingsRoute(page: "localGifts", item: "owned")?.destination, "localGifts/balance")
        XCTAssertEqual(RegramSettingsRoute(page: "pro.appearance", item: "appIcon")?.destination, "settings.appearance/appIcon")
        XCTAssertEqual(RegramSettingsRoute(page: "pro.notifications", item: "hideTabBarPermissionWarnings")?.destination, "settings.appearance/hideTabBarPermissionWarnings")
        XCTAssertNil(RegramSettingsRoute(page: "bottomBar", item: "search"))
        XCTAssertNil(RegramSettingsRoute(page: "settings.chatList", item: "disableDeleteChatSwipeOption"))
        XCTAssertEqual(RegramSettingsRoute(page: "bottomBar", item: "width")?.destination, "bottomBar/width")
        XCTAssertEqual(RegramSettingsRoute(page: "bottomBar", item: "labels")?.destination, "bottomBar/labels")
        XCTAssertEqual(RegramSettingsRoute(page: "bottomBar", item: "calls")?.destination, "bottomBar/calls")
        XCTAssertTrue(RegramSettingsCatalog.results(query: "mentionAsUserIdLink", language: "en").contains { $0.destination == "pro.input/mentionAsUserIdLink" })
    }

    func testBackupUsesSourceCategoriesAndExcludesCredentialsAndPremium() throws {
        var settings = RegramAccountSettings()
        settings["forceEmojiTab"] = .bool(true)
        settings["showProfileId"] = .bool(true)
        settings["localPremium"] = .bool(true)
        settings["features.hideTabBarPermissionWarnings"] = .bool(true)
        settings["clipboardOriginalImages"] = .bool(false)
        settings.values["apiKey"] = .string("test-only-placeholder")
        let messages = RegramSettingsBackup(settings: settings, categories: [.messages])
        XCTAssertEqual(messages.values["forceEmojiTab"], .bool(true))
        XCTAssertNil(messages.values["showProfileId"])
        let privacy = RegramSettingsBackup(settings: settings, categories: [.privacy])
        XCTAssertEqual(privacy.values["showProfileId"], .bool(true))
        XCTAssertNil(privacy.values["localPremium"])
        XCTAssertNil(privacy.values["apiKey"])
        XCTAssertFalse(RegramSettingsScope.includesNotifications)
        let appearance = RegramSettingsBackup(settings: settings, categories: [.appearance])
        XCTAssertEqual(appearance.values["features.hideTabBarPermissionWarnings"], .bool(true))
        let media = RegramSettingsBackup(settings: settings, categories: [.media])
        XCTAssertEqual(media.values["clipboardOriginalImages"], .bool(false))
        let restored = try RegramSettingsBackup.decode(messages.encoded()).applying(to: RegramAccountSettings())
        XCTAssertTrue(restored["forceEmojiTab"].bool)
    }

    func testLegacyBackupReplacesCanonicalNavigationAndNativeCallState() throws {
        var settings = RegramAccountSettings()
        var layout = RegramBottomBarSettings()
        layout.showLabels = false
        layout.apply(to: &settings)
        let backup = RegramSettingsBackup(values: ["showTabNames": .bool(true), "hideTabBar": .bool(true), "native.showCallsTab": .bool(false), "rememberLastFolder": .bool(true), "native.enableVoipTcp": .bool(true)])
        let restored = try RegramSettingsBackup.decode(backup.encoded()).applying(to: settings)
        let restoredLayout = RegramBottomBarSettings(settings: restored)
        XCTAssertTrue(restoredLayout.showLabels)
        XCTAssertTrue(restoredLayout.isBottomBarVisible)
        XCTAssertTrue(restoredLayout.automaticWidth)
        XCTAssertFalse(restoredLayout.isVisible(.calls))
        XCTAssertEqual(restored["features.chatListStartupFolderMode"], .string("last"))
        XCTAssertTrue(restored["enableVoipTcp"].bool)
        let reset = RegramSettingsBackup(values: [:]).applying(to: restored, categories: [], resetCategories: [.media])
        XCTAssertFalse(reset["enableVoipTcp"].bool)
        XCTAssertEqual(reset["features.chatListStartupFolderMode"], .string("last"))
    }

    func testBackupPreservesNativeCallPanelIndependentlyOfContactLayout() throws {
        for calls in [false, true] {
            var settings = RegramAccountSettings()
            var layout = RegramBottomBarSettings()
            layout.hide(.contacts)
            layout.apply(to: &settings)
            settings["native.showCallsTab"] = .bool(calls)
            let backup = try RegramSettingsBackup.decode(RegramSettingsBackup(settings: settings).encoded())
            XCTAssertEqual(backup.values["native.showCallsTab"], .bool(calls))
            let restored = backup.applying(to: RegramAccountSettings())
            XCTAssertEqual(restored["native.showCallsTab"], .bool(calls))
            XCTAssertEqual(RegramBottomBarSettings(settings: restored).visibleNavigationItems, [.chats, .settings])
        }
    }

    func testRetiredDeleteSwipeOptionDoesNotOverrideTheUnifiedSwipePolicy() throws {
        XCTAssertNil(RegramSetting.byKey["disableDeleteChatSwipeOption"])
        XCTAssertFalse(RegramSetting.availableKeys.contains("disableDeleteChatSwipeOption"))
        XCTAssertFalse(RegramSettingsCatalog.sourceEntries.contains { $0.key == "disableDeleteChatSwipeOption" })
        let backup = RegramSettingsBackup(values: ["disableDeleteChatSwipeOption": .bool(true), "features.chatListSwipeAction": .string("quick")])
        let restored = try RegramSettingsBackup.decode(backup.encoded()).applying(to: RegramAccountSettings())
        XCTAssertNil(restored.values["disableDeleteChatSwipeOption"])
        XCTAssertEqual(RegramChatListPolicy.swipeAction(settings: restored), .quickActions)
        let legacy = RegramAccountSettings(values: ["disableDeleteChatSwipeOption": .bool(true), "features.chatListSwipeAction": .string("both")])
        XCTAssertEqual(RegramChatListPolicy.swipeAction(settings: legacy), .both)
    }

    func testMediaLoadingExperimentCannotBeEnabledByLegacyMacPreferencesOrBackup() throws {
        XCTAssertNil(RegramSetting.byKey["mediaLoadingExperiment"])
        XCTAssertFalse(RegramSetting.availableKeys.contains("mediaLoadingExperiment"))
        XCTAssertNil(RegramSettingsRoute(page: "settings.media", item: "mediaLoadingExperiment"))
        XCTAssertFalse(RegramSettingsCatalog.sourceEntries.contains { $0.key == "mediaLoadingExperiment" })
        let legacy = RegramAccountSettings(values: ["mediaLoadingExperiment": .bool(true)])
        XCTAssertFalse(legacy["mediaLoadingExperiment"].bool)
        let backup = RegramSettingsBackup(settings: legacy, categories: [.media])
        let restored = try RegramSettingsBackup.decode(backup.encoded()).applying(to: RegramAccountSettings())
        XCTAssertNil(backup.values["mediaLoadingExperiment"])
        XCTAssertFalse(restored["mediaLoadingExperiment"].bool)
    }

    func testBackupRejectsInvalidSourceRangesAndRetainsValidImportedStickerSize() throws {
        let valid = RegramSettingsBackup(values: ["stickerSize": .integer(200), "recentStickerLimit": .integer(1000)])
        let restored = try RegramSettingsBackup.decode(valid.encoded()).applying(to: RegramAccountSettings())
        XCTAssertEqual(restored["stickerSize"], .integer(200))
        for values: [String: RegramValue] in [["outgoingPhotoQuality": .integer(101)], ["tabBarWidthPercent": .integer(49)], ["native.enableVoipTcp": .string("true")]] {
            XCTAssertThrowsError(try RegramSettingsBackup.decode(RegramSettingsBackup(values: values).encoded()))
        }
    }
}
