import XCTest
@testable import RegramCore

final class RegramAppearanceParityTests: XCTestCase {
    func testSourceBottomBarDefaultsAndRoundTrip() {
        let layout = RegramBottomBarSettings()
        XCTAssertEqual(layout.bottomItems, [.contacts, .calls, .chats, .settings])
        XCTAssertTrue(layout.automaticWidth)
        XCTAssertTrue(layout.topSearchVisible)
        XCTAssertTrue(layout.showLabels)
        XCTAssertEqual(layout.searchMode, .hidden)
        XCTAssertEqual(layout.hiddenItems, [.search])
        XCTAssertEqual(RegramBottomBarSettings(storedValues: layout.storedValues), layout)
        XCTAssertEqual(layout.storedValues["alignment"], "overallCenter")
    }

    func testRuntimeKeepsSupportedOptionsAndRecoversRemovedLayoutControls() {
        var old = RegramAccountSettings(values: ["sidebarOrder": .strings(["settings", "chats", "calls", "contacts"]), "sidebarHiddenTabs": .strings(["contacts", "settings"])])
        let migrated = RegramBottomBarSettings(settings: old)
        XCTAssertEqual(migrated.bottomItems, [.calls, .chats, .settings])
        XCTAssertFalse(migrated.isVisible(.contacts))
        XCTAssertTrue(migrated.isVisible(.settings))
        let canonical = RegramBottomBarSettings(storedValues: ["items": "calls,calls", "hidden": "contacts,chats,settings", "search": "button", "external": "settings", "fill": "83", "visible": "false", "labels": "false", "topSearch": "false", "automaticWidth": "true"])
        canonical.apply(to: &old)
        let supported = RegramBottomBarSettings(settings: old)
        XCTAssertTrue(supported.isVisible(.chats))
        XCTAssertTrue(supported.isVisible(.settings))
        XCTAssertFalse(supported.isVisible(.contacts))
        XCTAssertTrue(supported.isBottomBarVisible)
        XCTAssertTrue(supported.showLabels)
        XCTAssertTrue(supported.topSearchVisible)
        XCTAssertFalse(supported.automaticWidth)
        XCTAssertEqual(supported.searchMode, .hidden)
        XCTAssertFalse(supported.isVisible(.search))
        XCTAssertNil(supported.externalItem)
        XCTAssertEqual(supported.buttonWidthFillRatio, 83)
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
