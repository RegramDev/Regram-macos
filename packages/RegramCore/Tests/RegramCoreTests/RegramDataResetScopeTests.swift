import XCTest
@testable import RegramCore

final class RegramDataResetScopeTests: XCTestCase {
    func testResetScopeNeverTargetsParentOrAnotherApplication() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RegramResetTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = try XCTUnwrap(RegramDataResetScope.applicationDirectory(root: root))
        XCTAssertEqual(selected.lastPathComponent, "app.regram.macos")
        XCTAssertNotEqual(selected, root)
        let other = root.appendingPathComponent("other-client")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: other)
        XCTAssertNil(RegramDataResetScope.applicationDirectory(root: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }

    func testKeychainResetOnlyOwnsExplicitRegramNamespaces() {
        XCTAssertTrue(RegramDataResetScope.ownsKeychainService("app.regram.macos.Regram.Services"))
        XCTAssertTrue(RegramDataResetScope.ownsKeychainService("org.telegram.scoped.app.regram.macos.stable/org.telegram.passcode.v1"))
        for service in ["org.telegram.passcode.v1", "org.telegram.scoped.debug/org.telegram.passcode.v1", "org.telegram.scoped.app.regram.macos.evil", "org.telegram.scoped.app.regram.macos.evil/org.telegram.passcode.v1", "com.apple.account", "app.regram.macos.other.Regram.Services"] {
            XCTAssertFalse(RegramDataResetScope.ownsKeychainService(service))
        }
    }

    func testGroupResetRejectsLookalikesAndMismatchedPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RegramGroupResetTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(RegramDataResetScope.ownsAppGroupIdentifier("group.app.regram.macos"))
        XCTAssertFalse(RegramDataResetScope.ownsAppGroupIdentifier("otherapp.regram.macos-copy"))
        let identifier = "group.app.regram.macos"
        let group = root.appendingPathComponent(identifier, isDirectory: true)
        XCTAssertNotNil(RegramDataResetScope.groupDirectory(group, identifier: identifier))
        XCTAssertNil(RegramDataResetScope.groupDirectory(root.appendingPathComponent("otherapp.regram.macos-copy"), identifier: "otherapp.regram.macos-copy"))
        XCTAssertNil(RegramDataResetScope.groupDirectory(root.appendingPathComponent("different"), identifier: identifier))
        let other = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: group, withDestinationURL: other)
        XCTAssertNil(RegramDataResetScope.groupDirectory(group, identifier: identifier))
    }
}
