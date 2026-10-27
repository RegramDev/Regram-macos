import XCTest
@testable import RegramCore

final class RegramLanguagePackTests: XCTestCase {
    func testPlatformOverridesApplyToCompatibilityKeys() {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            for key in ["Summary.EnabledNotice", "LLMTranslation.ConnectionNotice", "MessageFilter.Rules.Notice", "Settings.SendWithReturnKey"] {
                XCTAssertEqual(regramLocalizedString("ios." + key, languageCode: language), regramLocalizedString(key, languageCode: language))
            }
        }
    }

    func testChineseVariantsAndFallback() {
        for code in ["zh-Hant", "zh_TW", "zh-HK-raw", "zh-MO"] {
            XCTAssertEqual(RegramLanguagePack.language(code), "zh-Hant")
            XCTAssertEqual(regramLocalizedString("Settings.FolderTags", languageCode: code), "標籤檢視")
        }
        for code in ["zh", "zh_CN", "zh-SG", "zh-Hans-raw", "regram-zh-hans", "regram-zh-hans-raw", "zhcncc"] {
            XCTAssertEqual(RegramLanguagePack.language(code), "zh-Hans")
            XCTAssertEqual(regramLocalizedString("profile.dataCenter", languageCode: code), "数据中心")
        }
        XCTAssertEqual(regramLocalizedString("LanguagePack.Name", languageCode: "en-US"), "Regram English")
        XCTAssertEqual(regramLocalizedString("Settings.FolderTags", languageCode: "unknown"), "Folder Tags")
        XCTAssertEqual(regramLocalizedString("missing.fixture", languageCode: "zh"), "missing.fixture")
    }

    func testNativeSupplementDoesNotReplaceOtherLanguages() {
        XCTAssertEqual(RegramLanguagePack.nativeMacOSStrings(languageCode: "zh-Hans")["ChatExport.MenuTitle"], "导出聊天记录…")
        XCTAssertEqual(RegramLanguagePack.nativeMacOSStrings(languageCode: "regram-zh-hans")["ChatExport.MenuTitle"], "导出聊天记录…")
        XCTAssertEqual(RegramLanguagePack.nativeMacOSStrings(languageCode: "zh-Hant")["ChatExport.Title"], "匯出聊天")
        XCTAssertTrue(RegramLanguagePack.nativeMacOSStrings(languageCode: "fr").isEmpty)
        let reference = Set(RegramLanguagePack.strings(languageCode: "en").keys)
        XCTAssertFalse(reference.isEmpty)
        XCTAssertEqual(Set(RegramLanguagePack.strings(languageCode: "zh-Hans").keys), reference)
        XCTAssertEqual(Set(RegramLanguagePack.strings(languageCode: "zh-Hant").keys), reference)
    }
}
