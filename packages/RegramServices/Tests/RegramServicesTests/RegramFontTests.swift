import XCTest
import AppKit
import CoreText
import RegramCore
@testable import RegramServices

final class RegramFontTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("RegramFontTests-\(UUID().uuidString)", isDirectory: true) }

    private func fixture() throws -> URL {
        let url = URL(fileURLWithPath: "/System/Library/Fonts/Helvetica.ttc")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("System TTC fixture is unavailable") }
        return url
    }

    func testImportFacesRenameRestartAndDeleteFallback() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RegramFontStore(root: directory)
        let imported = try store.importFonts(url: fixture(), accountId: 1)
        XCTAssertFalse(imported.isEmpty)
        XCTAssertEqual(Set(imported.map(\.id)).count, imported.count)
        for face in imported { XCTAssertNotNil(store.font(importedId: face.id, size: 17)) }
        let selected = imported[0]
        try store.rename(id: selected.id, title: " Renamed font ")
        let restored = RegramFontStore(root: directory)
        XCTAssertEqual(restored.imported.first(where: { $0.id == selected.id })?.title, "Renamed font")
        XCTAssertNotNil(restored.font(importedId: selected.id, size: 19))
        try restored.remove(id: selected.id)
        XCTAssertNil(restored.font(importedId: selected.id, size: 19))
        if imported.count > 1 { XCTAssertNotNil(restored.font(importedId: imported[1].id, size: 17)) }
    }

    func testImportedFontAccountRemovalPreservesAnotherAccountsSelection() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RegramFontStore(root: directory)
        let imported = try store.importFonts(url: fixture(), accountId: 101)
        let selected = try XCTUnwrap(imported.first)
        var settings = RegramAccountSettings()
        settings["fontImportedLatin"] = .string(selected.id)
        store.retainSelections(settings: settings, accountId: 202)
        try store.removeAccount(accountId: 101)
        XCTAssertEqual(store.imported.map(\.id), [selected.id])
        XCTAssertNotNil(store.font(importedId: selected.id, size: 17))
        try store.removeAccount(accountId: 202)
        XCTAssertTrue(store.imported.isEmpty)
        XCTAssertEqual(store.storageBytes(downloads: false), 0)
        XCTAssertNil(store.font(importedId: selected.id, size: 17))
    }

    func testInvalidOversizedAndTamperedFilesAreRejected() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("bad.ttf")
        try Data("not a font".utf8).write(to: source)
        let store = RegramFontStore(root: directory.appendingPathComponent("Store"))
        XCTAssertThrowsError(try store.importFonts(url: source))
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(RegramFontStore.maximumImportBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try store.importFonts(url: source))
        let valid = try store.importFonts(url: fixture())
        let selected = try XCTUnwrap(valid.first)
        let selection = try XCTUnwrap(RegramFontSelection(id: selected.id))
        let retained = directory.appendingPathComponent("Store/Imported/\(selection.fileId).font")
        try Data("tampered".utf8).write(to: retained)
        let restored = RegramFontStore(root: directory.appendingPathComponent("Store"))
        XCTAssertNil(restored.font(importedId: selected.id, size: 17))
    }

    func testFontScopeAndMissingFaceFallback() {
        var settings = RegramAccountSettings()
        settings["fontFamily"] = .string("rounded")
        settings["fontApplyToMessages"] = .bool(false)
        settings["fontApplyToInterface"] = .bool(true)
        let base = NSFont.systemFont(ofSize: 17)
        XCTAssertNil(RegramFonts.font(base: base, settings: settings, area: .messages))
        XCTAssertNotNil(RegramFonts.font(base: base, settings: settings, area: .interface))
        settings["fontFamily"] = .string("system")
        settings["fontImportedLatin"] = .string(String(repeating: "a", count: 64) + ":2")
        XCTAssertNil(RegramFonts.font(base: base, settings: settings, area: .interface))
        XCTAssertNil(RegramFontSelection(id: "../../escape"))
        XCTAssertNil(RegramFontSelection(id: String(repeating: "a", count: 64) + ":0"))
    }

    func testImportedFontSurvivesNativeTextLayoutAndEmphasis() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Times New Roman.ttf")
        guard FileManager.default.fileExists(atPath: source.path) else { throw XCTSkip("System font fixture is unavailable") }
        let store = RegramFontStore(root: directory)
        let selection = try XCTUnwrap(try store.importFonts(url: source).first)
        let selected = try XCTUnwrap(store.font(importedId: selection.id, size: 19))
        var settings = RegramAccountSettings()
        settings["fontImportedLatin"] = .string(selection.id)
        for (weight, italic) in [(NSFont.Weight.regular, false), (.bold, false), (.regular, true), (.bold, true)] {
            var base = NSFont.systemFont(ofSize: 19, weight: weight)
            if italic { base = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask) }
            let font = try XCTUnwrap(RegramFonts.font(base: base, settings: settings, area: .messages, store: store))
            XCTAssertEqual(font.familyName, selected.familyName)
            XCTAssertEqual(font.pointSize, base.pointSize)
            let run = try renderedFont(font, text: "Regram Aa 0123", at: 0)
            XCTAssertEqual(CTFontCopyFamilyName(run) as String, selected.familyName)
            XCTAssertNotEqual(CTFontCopyPostScriptName(run) as String, CTFontCopyPostScriptName(base as CTFont) as String)
            if weight == .bold { XCTAssertTrue(CTFontGetSymbolicTraits(run).contains(.boldTrait)) }
            if italic { XCTAssertTrue(CTFontGetSymbolicTraits(run).contains(.italicTrait) || CTFontGetMatrix(run).c != 0) }
        }
        settings["fontApplyToMessages"] = .bool(false)
        XCTAssertNil(RegramFonts.font(base: .systemFont(ofSize: 19), settings: settings, area: .messages, store: store))
        XCTAssertNotNil(RegramFonts.font(base: .systemFont(ofSize: 19), settings: settings, area: .interface, store: store))
        settings["fontApplyToInterface"] = .bool(false)
        XCTAssertNil(RegramFonts.font(base: .systemFont(ofSize: 19), settings: settings, area: .interface, store: store))
        XCTAssertNotNil(RegramFonts.font(base: .systemFont(ofSize: 19), settings: settings, area: .preview, store: store))
    }

    func testIndependentChineseSelectionAffectsActualGlyphRunsAndCanBeReset() throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = URL(fileURLWithPath: "/System/Library/Fonts/Hiragino Sans GB.ttc")
        guard FileManager.default.fileExists(atPath: source.path) else { throw XCTSkip("System CJK fixture is unavailable") }
        let store = RegramFontStore(root: directory)
        let selection = try XCTUnwrap(try store.importFonts(url: source).first(where: { $0.chinese }))
        let selected = try XCTUnwrap(store.font(importedId: selection.id, size: 19))
        var settings = RegramAccountSettings()
        settings["fontImportedChinese"] = .string(selection.id)
        let base = NSFont.systemFont(ofSize: 19)
        let font = try XCTUnwrap(RegramFonts.font(base: base, settings: settings, area: .messages, store: store))
        for index in [1, 2, 3] {
            let run = try renderedFont(font, text: "A中文，", at: index)
            XCTAssertEqual(CTFontCopyFamilyName(run) as String, selected.familyName)
        }
        let latin = try renderedFont(font, text: "A中文，", at: 0)
        XCTAssertNotEqual(CTFontCopyFamilyName(latin) as String, selected.familyName)
        settings["fontImportedChinese"] = .string("")
        XCTAssertNil(RegramFonts.font(base: base, settings: settings, area: .messages, store: store))
        settings["fontImportedLatin"] = .string(selection.id)
        let combined = try XCTUnwrap(RegramFonts.font(base: base, settings: settings, area: .messages, store: store))
        settings["fontImportedChinese"] = .string(selection.id)
        let separated = try XCTUnwrap(RegramFonts.font(base: base, settings: settings, area: .messages, store: store))
        XCTAssertEqual(CTFontCopyFamilyName(try renderedFont(separated, text: "A中文，", at: 3)) as String, selected.familyName)
        XCTAssertEqual(CTFontCopyFamilyName(try renderedFont(combined, text: "A中文，", at: 0)) as String, selected.familyName)
    }

    private func renderedFont(_ font: NSFont, text: String, at index: Int) throws -> CTFont {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        let run = try XCTUnwrap(runs.first(where: { run in
            let range = CTRunGetStringRange(run)
            return range.location <= index && index < range.location + range.length
        }))
        XCTAssertGreaterThan(CTRunGetGlyphCount(run), 0)
        let attributes = CTRunGetAttributes(run) as NSDictionary
        return try XCTUnwrap(attributes[kCTFontAttributeName] as? NSFont) as CTFont
    }
}
