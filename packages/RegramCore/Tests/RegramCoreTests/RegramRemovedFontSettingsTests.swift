import XCTest
@testable import RegramCore

final class RegramRemovedFontSettingsTests: XCTestCase {
    func testFontCustomizationHasNoSettingsEntryOrDeepLink() throws {
        XCTAssertFalse(RegramSettingsCatalog.entries.contains { $0.page == "fonts" || ($0.page == "pro.appearance" && $0.key == "fonts") })
        XCTAssertNil(RegramSettingsRoute(url: try XCTUnwrap(URL(string: "regram://settings?page=fonts"))))
    }

    func testMessagePreviewLineSettingRemainsAvailable() {
        XCTAssertNotNil(RegramSetting.byKey["chatListLines"])
        XCTAssertTrue(RegramSettingsCatalog.entries.contains { $0.key == "chatListLines" })
    }
}
