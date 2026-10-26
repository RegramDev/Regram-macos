import Foundation
import XCTest
@testable import RegramCore

final class RegramFilterImportTests: XCTestCase {
    private func backup(_ rules: [RGMessageFilterRule]) throws -> RegramFilterImport {
        try RegramFilterImport(data: JSONEncoder().encode(rules))
    }

    func testCurrentIOSSchemaPreservesAllRuleFields() throws {
        let rule = RGMessageFilterRule(id: "ios-rule", pattern: "广告|spam", isRegex: true, peerIds: [Int64.max, -100, 9007199254740993], isEnabled: false, isException: true)
        let value = try backup([rule])
        XCTAssertEqual(value.rules, [rule])
        XCTAssertEqual(try JSONDecoder().decode([RGMessageFilterRule].self, from: value.data), [rule])
    }

    func testLegacyIOSSchemaUsesSourceDefaultsAndPrecisePeerIds() throws {
        let data = Data("[{\"id\":\"legacy\",\"pattern\":\"spam\",\"isRegex\":false,\"peerIds\":[9007199254740993]}]".utf8)
        let rule = try XCTUnwrap(RegramFilterImport(data: data).rules.first)
        XCTAssertTrue(rule.isEnabled)
        XCTAssertFalse(rule.isException)
        XCTAssertEqual(rule.peerIds, [9007199254740993])
    }

    func testUnrelatedAndMalformedJSONCannotExposeImport() {
        for value in ["[]", "{}", "{\"messageFilterRules\":[]}", "[1]", "not-json", "[{\"id\":\"x\",\"pattern\":\"spam\",\"isRegex\":\"false\",\"peerIds\":[]}]", "[{\"id\":\"x\",\"pattern\":\"spam\",\"isRegex\":false,\"peerIds\":[\"1\"]}]"] {
            XCTAssertThrowsError(try RegramFilterImport(data: Data(value.utf8)), value)
        }
    }

    func testContentIsRecognizedWithoutFilenameConvention() throws {
        let original = try backup([RGMessageFilterRule(pattern: "spam")])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try original.data.write(to: url)
        XCTAssertEqual(try RegramFilterImport.read(from: url), original)
    }

    func testSourceSchemaKeepsInvalidRegexInertInsteadOfRejectingTheBackup() throws {
        let value = try backup([RGMessageFilterRule(pattern: "[", isRegex: true)])
        XCTAssertFalse(try XCTUnwrap(value.rules.first).isValid)
        let result = value.merging(into: [])
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertFalse(RGMessageFilter.shouldHide(text: "visible", peerId: 1, rules: result.rules))
    }

    func testOversizedDataAndFilesAreRejected() throws {
        let data = Data(repeating: 0x20, count: RegramFilterImport.maximumBytes + 1)
        XCTAssertThrowsError(try RegramFilterImport(data: data))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        XCTAssertThrowsError(try RegramFilterImport.read(from: url))
    }

    func testPreviewAndMergeKeepExistingDefinitionsAndRegenerateConflictingIds() throws {
        let existing = RGMessageFilterRule(id: "shared", pattern: "keep existing", peerIds: [1, 2], isEnabled: false)
        let duplicate = RGMessageFilterRule(id: "duplicate", pattern: existing.pattern, peerIds: [2, 1, 2])
        let conflict = RGMessageFilterRule(id: "shared", pattern: "new rule", isRegex: true, peerIds: [3], isException: true)
        let value = try backup([duplicate, conflict, conflict])
        let plan = value.plan(existing: [existing])
        XCTAssertEqual(plan.entries.map(\.disposition), [.duplicate, .conflictingIdentifier, .duplicate])
        XCTAssertEqual(plan.addedCount, 1)
        XCTAssertEqual(plan.duplicateCount, 2)
        XCTAssertEqual(plan.conflictingIdentifierCount, 1)
        let result = value.merging(into: [existing])
        XCTAssertEqual(result.rules.first, existing)
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertNotEqual(result.rules.last?.id, conflict.id)
        XCTAssertTrue(result.rules.last?.hasSameDefinition(as: conflict) == true)
        XCTAssertEqual(value.merging(into: result.rules).addedCount, 0)
    }

    func testConfirmationRebasesOnTheCurrentRules() throws {
        let imported = RGMessageFilterRule(pattern: "incoming")
        let value = try backup([imported])
        XCTAssertEqual(value.plan(existing: []).addedCount, 1)
        let concurrent = RGMessageFilterRule(id: "newer", pattern: imported.pattern, isEnabled: false)
        let result = value.merging(into: [concurrent])
        XCTAssertEqual(result.addedCount, 0)
        XCTAssertEqual(result.rules, [concurrent])
    }
}
