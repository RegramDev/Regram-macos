import RegramCore
import XCTest
@testable import ChatUI

final class RegramComposerPreferenceTests: XCTestCase {
    private func preferences(_ mask: Int) -> RegramComposerPreferences {
        var settings = RegramAccountSettings()
        settings["features.autoInlineBotEnabled"] = .bool(mask & 1 != 0)
        settings["disableLinkPreview"] = .bool(mask & 2 != 0)
        settings["fixLinkPreviews"] = .bool(mask & 4 != 0)
        settings["linkPreviewXHost"] = .string(mask & 8 != 0 ? "example.test" : RGLinkPreviewRules.defaultXHost)
        settings["linkPreviewInstagramHost"] = .string(mask & 16 != 0 ? "example.test" : RGLinkPreviewRules.defaultInstagramHost)
        return RegramComposerPreferences(settings: settings)
    }

    func testEveryComposerCombinationCancelsOnlyItsOwnQueryAndDefersHiddenWork() {
        var cases = 0
        for before in 0..<32 {
            for after in 0..<32 {
                for visible in [false, true] {
                    var state = RegramComposerRefreshState()
                    let initial = state.update(preferences(before), visible: true)
                    XCTAssertTrue(initial.cancel.isEmpty && initial.reload.isEmpty)
                    var expected: RegramComposerRefresh = []
                    if (before ^ after) & 1 != 0 { expected.insert(.context) }
                    if (before ^ after) & 30 != 0 { expected.insert(.preview) }
                    let changes = state.update(preferences(after), visible: visible)
                    XCTAssertEqual(changes.cancel, expected)
                    XCTAssertEqual(changes.reload, visible ? expected : [])
                    let returned = state.update(preferences(after), visible: true)
                    XCTAssertTrue(returned.cancel.isEmpty)
                    XCTAssertEqual(returned.reload, visible ? [] : expected)
                    let repeated = state.update(preferences(after), visible: true)
                    XCTAssertTrue(repeated.cancel.isEmpty && repeated.reload.isEmpty)
                    cases += 1
                }
            }
        }
        print("COMPOSER_SETTING_TRANSITIONS cases=\(cases)")
    }

    func testHiddenChangesMergeAndResumeOnceWithTheLatestSettings() {
        var state = RegramComposerRefreshState()
        _ = state.update(preferences(0), visible: true)
        XCTAssertEqual(state.update(preferences(2), visible: false).cancel, .preview)
        XCTAssertEqual(state.update(preferences(3), visible: false).cancel, .context)
        let hidden = state.update(preferences(31), visible: false)
        XCTAssertEqual(hidden.cancel, .preview)
        XCTAssertTrue(hidden.reload.isEmpty)
        let returned = state.update(preferences(31), visible: true)
        XCTAssertTrue(returned.cancel.isEmpty)
        XCTAssertEqual(returned.reload, [.context, .preview])
        let repeated = state.update(preferences(31), visible: true)
        XCTAssertTrue(repeated.cancel.isEmpty && repeated.reload.isEmpty)
    }

    func testHiddenToggleBackStillReplacesTheCancelledRequest() {
        var state = RegramComposerRefreshState()
        _ = state.update(preferences(0), visible: true)
        _ = state.update(preferences(2), visible: false)
        _ = state.update(preferences(0), visible: false)
        XCTAssertEqual(state.update(preferences(0), visible: true).reload, .preview)
        XCTAssertTrue(state.update(preferences(0), visible: true).reload.isEmpty)
    }

    func testFirstHiddenConfigurationDoesNotStartQueries() {
        var state = RegramComposerRefreshState()
        let hidden = state.update(preferences(31), visible: false)
        XCTAssertTrue(hidden.cancel.isEmpty && hidden.reload.isEmpty)
        let shown = state.update(preferences(31), visible: true)
        XCTAssertTrue(shown.cancel.isEmpty && shown.reload.isEmpty)
    }

    func testFormattingTranslationMediaAndPrivacyChangesKeepBothQueries() {
        var settings = RegramAccountSettings()
        settings["features.autoInlineBotEnabled"] = .bool(true)
        settings["fixLinkPreviews"] = .bool(true)
        let initial = RegramComposerPreferences(settings: settings)
        var state = RegramComposerRefreshState()
        _ = state.update(initial, visible: true)
        for (key, value) in [("panguSpacing", RegramValue.bool(true)), ("defaultOutgoingFormatting", .string("bold")), ("translationBackend", .string("llm")), ("transcriptionBackend", .string("apple")), ("allowSavingProtectedContent", .bool(true)), ("antiRevoke", .bool(true)), ("outgoingPhotoQuality", .integer(72)), ("hideStories", .bool(true))] {
            settings[key] = value
            let current = RegramComposerPreferences(settings: settings)
            XCTAssertEqual(current, initial, key)
            let changes = state.update(current, visible: true)
            XCTAssertTrue(changes.cancel.isEmpty && changes.reload.isEmpty, key)
        }
        XCTAssertEqual(RegramComposerPreferences.preferenceKeys, ["features.autoInlineBotEnabled", "disableLinkPreview", "fixLinkPreviews", "linkPreviewXHost", "linkPreviewInstagramHost"])
    }
}
