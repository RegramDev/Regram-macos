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
        let marker = RegramRevokedMarker(style: .text, text: "\u{202E} removed ", color: "abcdef")
        marker.apply(to: &settings)
        let decoded = try JSONDecoder().decode(RegramAccountSettings.self, from: JSONEncoder().encode(settings))
        let restored = RegramRevokedMarker(settings: decoded)
        XCTAssertEqual(restored.text, "removed")
        XCTAssertEqual(restored.color, "#ABCDEF")
        XCTAssertEqual(restored.label(defaultText: "Deleted"), "removed")
        XCTAssertNil(RegramRevokedMarker(style: .none).label(defaultText: "Deleted"))
        XCTAssertEqual(RegramRevokedMarker(style: .text).label(defaultText: "Deleted"), "Deleted")
    }
}
