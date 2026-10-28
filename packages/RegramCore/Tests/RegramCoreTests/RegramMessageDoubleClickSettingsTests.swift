import XCTest
@testable import RegramCore

final class RegramMessageDoubleClickSettingsTests: XCTestCase {
    func testBothActionsCanBeFoundAndOpenedInEverySupportedLanguage() throws {
        let keys = ["messageDoubleTapAction", "messageDoubleTapActionWithoutEditPermission"]
        for (language, query) in [("en", "double click"), ("zh-Hans", "双击"), ("zh-Hant", "雙擊")] {
            let results = RegramSettingsCatalog.results(query: query, language: language)
            for key in keys {
                let entry = try XCTUnwrap(results.first { $0.key == key }, key + " " + language)
                XCTAssertEqual(entry.page, "settings.messageActions")
                let route = try XCTUnwrap(RegramSettingsRoute(url: try XCTUnwrap(URL(string: "regram://settings?page=settings.messageActions&item=" + key))))
                XCTAssertEqual(route.page, entry.page)
                XCTAssertEqual(route.item, key)
            }
        }
    }

    func testEveryAvailableActionHasLocalizedChoices() throws {
        let actions = RGMessageDoubleClickAction.allCases.map(\.rawValue)
        XCTAssertEqual(try XCTUnwrap(RegramSetting.byKey["messageDoubleTapAction"]).choices.map(\.string), actions)
        XCTAssertEqual(try XCTUnwrap(RegramSetting.byKey["messageDoubleTapActionWithoutEditPermission"]).choices.map(\.string), ["sameAsUnified"] + actions)
        for language in ["en", "zh-Hans", "zh-Hant"] {
            for action in actions + ["sameAsUnified"] {
                let key = "DoubleTap.Action." + action
                let title = regramLocalizedString(key, languageCode: language)
                XCTAssertFalse(title.isEmpty)
                XCTAssertNotEqual(title, key)
            }
        }
    }

    func testUnavailableEditingOverrideResolvesEveryActionIndependently() {
        for unified in RGMessageDoubleClickAction.allCases {
            var settings = RegramAccountSettings()
            settings["messageDoubleTapAction"] = .string(unified.rawValue)
            for fallback in RGMessageDoubleClickAction.allCases {
                settings["messageDoubleTapActionWithoutEditPermission"] = .string(fallback.rawValue)
                XCTAssertEqual(RGMessageDoubleClickAction.resolved(settings: settings, canEdit: true), unified)
                XCTAssertEqual(RGMessageDoubleClickAction.resolved(settings: settings, canEdit: false), fallback == .edit ? .sendReaction : fallback)
            }
            settings["messageDoubleTapActionWithoutEditPermission"] = .string("sameAsUnified")
            XCTAssertEqual(RGMessageDoubleClickAction.resolved(settings: settings, canEdit: false), unified == .edit ? .sendReaction : unified)
        }
    }
}
