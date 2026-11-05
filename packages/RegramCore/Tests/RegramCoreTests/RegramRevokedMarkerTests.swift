import XCTest
@testable import RegramCore

final class RegramRevokedMarkerTests: XCTestCase {
    func testMarkerNormalizationAndColorValidation() {
        XCTAssertEqual(RegramRevokedMarker.normalizedText(" \u{202E}Deleted\n\u{2066} "), "Deleted")
        XCTAssertEqual(RegramRevokedMarker.normalizedText(String(repeating: "好", count: 40)).count, 24)
        XCTAssertEqual(RegramRevokedMarker.rgb(" #aB01fF "), 0xAB01FF)
        XCTAssertNil(RegramRevokedMarker.rgb("#12345"))
        XCTAssertNil(RegramRevokedMarker.rgb("#12345G"))
    }

    func testAppliedMarkerRoundTripsAndHiddenStyleHasNoLabel() throws {
        var settings = RegramAccountSettings()
        let marker = RegramRevokedMarker(style: .text, text: "\u{202E} removed ", color: "abcdef", dimMessages: false)
        marker.apply(to: &settings)
        let decoded = try JSONDecoder().decode(RegramAccountSettings.self, from: JSONEncoder().encode(settings))
        let restored = RegramRevokedMarker(settings: decoded)
        XCTAssertEqual(restored.text, "removed")
        XCTAssertEqual(restored.color, "#ABCDEF")
        XCTAssertFalse(restored.dimMessages)
        XCTAssertTrue(RegramRevokedMarker(settings: RegramAccountSettings()).dimMessages)
        XCTAssertEqual(restored.label(defaultText: "Deleted"), "removed")
        XCTAssertNil(RegramRevokedMarker(style: .none).label(defaultText: "Deleted"))
        XCTAssertEqual(RegramRevokedMarker(style: .text).label(defaultText: "Deleted"), "Deleted")
    }
    func testOpacityIsBackedUpAndTimerSettingsNeverEnableRevocationRetention() throws {
        var settings = RegramAccountSettings()
        settings["antiAutoDelete"] = .bool(true)
        settings["antiSelfDestruct"] = .bool(true)
        settings["revokedMarkerDimMessages"] = .bool(false)
        XCTAssertFalse(settings.shouldRetainRevokedMessage(peerId: 5, authorIsBot: false))
        XCTAssertFalse(RegramFilterSnapshot(settings: settings).shouldRetainRevokedMessage(peerId: 5, authorIsBot: false))
        let backup = RegramSettingsBackup(settings: settings, categories: [.privacy])
        let restored = try RegramSettingsBackup.decode(backup.encoded()).applying(to: RegramAccountSettings())
        XCTAssertFalse(RegramRevokedMarker(settings: restored).dimMessages)
        XCTAssertFalse(restored["antiRevoke"].bool)
        settings["antiRevoke"] = .bool(true)
        XCTAssertTrue(RegramFilterSnapshot(settings: settings).shouldRetainRevokedMessage(peerId: 5, authorIsBot: false))
        settings["antiRevokeSkipBots"] = .bool(true)
        XCTAssertFalse(RegramFilterSnapshot(settings: settings).shouldRetainRevokedMessage(peerId: 5, authorIsBot: true))
    }
}
