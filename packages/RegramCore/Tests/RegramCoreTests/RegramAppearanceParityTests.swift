import XCTest
@testable import RegramCore

final class RegramAppearanceParityTests: XCTestCase {
    func testBetaBottomBarDefaultsAndRoundTrip() {
        let layout = RegramBottomBarSettings()
        XCTAssertEqual(layout.bottomItems, [.contacts, .chats, .settings])
        XCTAssertTrue(layout.automaticWidth)
        XCTAssertTrue(layout.topSearchVisible)
        XCTAssertFalse(layout.showLabels)
        XCTAssertEqual(layout.searchMode, .hidden)
        XCTAssertEqual(layout.hiddenItems, [.calls, .search])
        XCTAssertEqual(RegramBottomBarSettings(storedValues: layout.storedValues), layout)
        XCTAssertEqual(layout.storedValues["alignment"], "overallCenter")
    }

    func testLegacyLayoutsPreserveContactVisibilityAndRestoreBetaPresentation() {
        var old = RegramAccountSettings(values: ["sidebarOrder": .strings(["settings", "chats", "calls", "contacts"]), "sidebarHiddenTabs": .strings(["contacts", "settings"])])
        let migrated = RegramBottomBarSettings(settings: old)
        XCTAssertEqual(migrated.bottomItems, [.chats, .settings])
        XCTAssertFalse(migrated.isVisible(.contacts))
        XCTAssertTrue(migrated.isVisible(.settings))
        let canonical = RegramBottomBarSettings(storedValues: ["items": "calls,calls", "hidden": "contacts,chats,settings", "search": "button", "external": "settings", "fill": "83", "visible": "false", "labels": "false", "topSearch": "false", "automaticWidth": "true"])
        canonical.apply(to: &old)
        let supported = RegramBottomBarSettings(settings: old)
        XCTAssertTrue(supported.isVisible(.chats))
        XCTAssertTrue(supported.isVisible(.settings))
        XCTAssertFalse(supported.isVisible(.contacts))
        XCTAssertTrue(supported.isBottomBarVisible)
        XCTAssertFalse(supported.showLabels)
        XCTAssertTrue(supported.topSearchVisible)
        XCTAssertTrue(supported.automaticWidth)
        XCTAssertEqual(supported.searchMode, .hidden)
        XCTAssertFalse(supported.isVisible(.search))
        XCTAssertNil(supported.externalItem)
        XCTAssertFalse(supported.isVisible(.calls))
        XCTAssertEqual(supported.buttonWidthFillRatio, 100)
    }

    func testContactTogglePersistsWithoutChangingOtherAccountSettings() {
        var settings = RegramAccountSettings(values: ["native.showContactsTab": .bool(false), "showMessageId": .bool(true)])
        var layout = RegramBottomBarSettings(settings: settings)
        XCTAssertEqual(layout.visibleNavigationItems, [.chats, .settings])
        layout.toggleHidden(.contacts)
        layout.apply(to: &settings)
        XCTAssertEqual(RegramBottomBarSettings(settings: settings).visibleNavigationItems, [.contacts, .chats, .settings])
        XCTAssertTrue(settings["showMessageId"].bool)
        layout.toggleHidden(.contacts)
        layout.apply(to: &settings)
        let restored = RegramSettingsBackup(settings: settings).applying(to: RegramAccountSettings())
        XCTAssertEqual(RegramBottomBarSettings(settings: restored).visibleNavigationItems, [.chats, .settings])
        XCTAssertEqual(RegramBottomBarSettings(settings: RegramAccountSettings()).visibleNavigationItems, [.contacts, .chats, .settings])
    }

    func testNativeBottomBarWidthAndLabelsSurviveChangesAndBackup() throws {
        var settings = RegramAccountSettings()
        var layout = RegramBottomBarSettings(settings: settings)
        layout.automaticWidth = false
        layout.buttonWidthFillRatio = 75
        layout.showLabels = true
        layout.apply(to: &settings)
        layout = RegramBottomBarSettings(settings: settings)
        layout.toggleHidden(.contacts)
        layout.apply(to: &settings)
        let backup = RegramSettingsBackup(settings: settings, categories: [.appearance])
        let restored = RegramBottomBarSettings(settings: try RegramSettingsBackup.decode(backup.encoded()).applying(to: RegramAccountSettings()))
        XCTAssertEqual(restored.buttonWidthFillRatio, 75)
        XCTAssertFalse(restored.automaticWidth)
        XCTAssertTrue(restored.showLabels)
        XCTAssertEqual(restored.visibleNavigationItems, [.chats, .settings])
        XCTAssertEqual(settings["showTabNames"], .bool(true))
        XCTAssertEqual(settings["tabBarWidthPercent"], .integer(75))
    }

    func testLegacyBottomBarPresentationAndWidthLimits() {
        let legacy = RegramBottomBarSettings(settings: RegramAccountSettings(values: ["showTabNames": .bool(true), "tabBarWidthPercent": .integer(80)]))
        XCTAssertTrue(legacy.showLabels)
        XCTAssertFalse(legacy.automaticWidth)
        XCTAssertEqual(legacy.buttonWidthFillRatio, 80)
        let automatic = RegramBottomBarSettings(settings: RegramAccountSettings(values: ["tabBarWidthPercent": .integer(0)]))
        XCTAssertEqual(automatic.buttonWidthFillRatio, 100)
        XCTAssertTrue(automatic.automaticWidth)
        var small = RegramBottomBarSettings(automaticWidth: false, buttonWidthFillRatio: 10)
        var settings = RegramAccountSettings()
        small.apply(to: &settings)
        small = RegramBottomBarSettings(settings: settings)
        XCTAssertEqual(small.buttonWidthFillRatio, 50)
    }

    func testExternalPlacementSearchAndHideRecovery() {
        var layout = RegramBottomBarSettings()
        layout.moveToExternal(.chats)
        XCTAssertEqual(layout.externalItem, .chats)
        XCTAssertFalse(layout.bottomItems.contains(.chats))
        layout.moveToExternal(.settings)
        XCTAssertEqual(layout.externalItem, .settings)
        XCTAssertTrue(layout.bottomItems.contains(.chats))
        layout.setSearchMode(.button)
        XCTAssertTrue(layout.isVisible(.search))
        layout.hide(.settings)
        XCTAssertTrue(layout.isVisible(.settings))
        layout.hide(.calls)
        XCTAssertFalse(layout.isVisible(.calls))
        layout.show(.calls)
        XCTAssertTrue(layout.isVisible(.calls))
        layout.moveToBottom(.settings, at: 0)
        XCTAssertNil(layout.externalItem)
        XCTAssertEqual(layout.bottomItems.first, .settings)
        layout.isBottomBarVisible = false
        XCTAssertTrue(layout.visibleBottomItems.isEmpty)
        layout.reset()
        XCTAssertEqual(layout, RegramBottomBarSettings())
    }

    func testAllSeventeenGroupVisibilityFlagsRemainIndependent() {
        XCTAssertEqual(RegramGroupProfileSettingItem.allCases.count, 17)
        var settings = RegramAccountSettings()
        for item in RegramGroupProfileSettingItem.allCases { XCTAssertFalse(item.isVisible(settings: settings)) }
        RegramGroupProfileSettingItem.admins.setVisible(true, settings: &settings)
        RegramGroupProfileSettingItem.reactions.setVisible(true, settings: &settings)
        XCTAssertTrue(RegramGroupProfileSettingItem.admins.isVisible(settings: settings))
        XCTAssertTrue(RegramGroupProfileSettingItem.reactions.isVisible(settings: settings))
        XCTAssertFalse(RegramGroupProfileSettingItem.permissions.isVisible(settings: settings))
        RegramGroupProfileSettingItem.admins.setVisible(false, settings: &settings)
        XCTAssertEqual(settings["features.groupProfileSettingItems"].string, "reactions")
    }

    func testSourceEligibilityGatesAndProfileBadges() {
        var settings = RegramAccountSettings()
        XCTAssertNil(settings.seasonalEffect)
        XCTAssertFalse(settings.isStoryStealthModeEnabled)
        settings["storyStealthMode"] = .bool(true)
        XCTAssertTrue(settings.isStoryStealthModeEnabled)
        settings["canUseStealthMode"] = .bool(false)
        XCTAssertFalse(settings.isStoryStealthModeEnabled)
        settings["nyStyle"] = .string("snow")
        XCTAssertNil(settings.seasonalEffect)
        settings["canUseNY"] = .bool(true)
        XCTAssertEqual(settings.seasonalEffect, "snow")
        settings["nyStyle"] = .string("default")
        XCTAssertNil(settings.seasonalEffect)
        XCTAssertEqual(RegramProfileBadge.badge(userId: 6860249), .developer)
        XCTAssertNil(RegramProfileBadge.badge(userId: 5602240478))
        XCTAssertNil(RegramProfileBadge.badge(userId: 7086851861))
        XCTAssertNil(RegramProfileBadge.badge(userId: 1))
    }

    func testBenchmarkCancellationAndRuleScopes() {
        let session = RGFilterBenchmarkSession()
        let old = session.begin()
        let current = session.begin()
        XCTAssertFalse(session.isActive(old))
        XCTAssertFalse(session.finish(old))
        XCTAssertTrue(session.isActive(current))
        session.cancel()
        XCTAssertNil(RGFilterBenchmark.measure(rules: [], shouldContinue: { session.isActive(current) }))
        var calls = 0
        let result = RGFilterBenchmark.measure(rules: [], now: { Double(calls) }, match: { _, _ in calls += 1; return false })
        XCTAssertEqual(calls, 100)
        XCTAssertEqual(result?.averageMilliseconds, 1000)
    }
}
