#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class AttributedStringMapperLinkTests: XCTestCase {
    let mapper = AttributedStringMapper()

    func test_attributes_link_addsVisibleStyling() {
        let dict = mapper.attributes(for: CharacterAttributes(link: "https://x.com"), style: .body)
        XCTAssertEqual(dict[.link] as? String, "https://x.com")
        // 6a: links render blue only — no underline (updated from single.rawValue assertion)
        XCTAssertNil(dict[.underlineStyle], "links must not be underlined in 6a")
        XCTAssertNotNil(dict[.foregroundColor], "links render with an explicit foreground color")
    }

    func test_readback_link_suppressesForegroundAndUnderline() {
        let dict: [NSAttributedString.Key: Any] = [
            .link: "https://x.com",
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: 16),
        ]
        let ca = mapper.characterAttributes(from: dict)
        XCTAssertEqual(ca.link, "https://x.com")
        XCTAssertFalse(ca.underline, "underline from link styling must not leak into the model")
        XCTAssertNil(ca.foreground, "blue from link styling must not leak into the model")
    }

    func test_readback_noLink_preservesUnderlineAndUsesCurrentThemeForeground() {
        for color in [NSColor.red, .black, .white] {
            let dict: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: 16),
            ]
            let ca = mapper.characterAttributes(from: dict)
            XCTAssertNil(ca.link)
            XCTAssertTrue(ca.underline)
            XCTAssertNil(ca.foreground)
            for foreground in [NSColor.black, .white] {
                let themed = AttributedStringMapper(styleSheet: .default, appearance: EditorAppearance(defaultForeground: foreground))
                let rendered = themed.attributes(for: ca, style: .body)
                XCTAssertEqual(rendered[.foregroundColor] as? NSColor, foreground)
                XCTAssertEqual(rendered[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
            }
        }
    }

    func test_roundTrip_linkOnly() {
        let dict = mapper.attributes(for: CharacterAttributes(link: "https://x.com"), style: .body)
        let ca = mapper.characterAttributes(from: dict)
        XCTAssertEqual(ca.link, "https://x.com")
        XCTAssertFalse(ca.underline)
        XCTAssertNil(ca.foreground)
    }

    func test_runs_fromAttributedString_linkRoundTripsAndSuppressesStyling() {
        let block = ParagraphBlock(id: BlockID("p"), runs: [
            TextRun(text: "see "),
            TextRun(text: "here", attributes: CharacterAttributes(link: "https://x.com")),
        ])
        let runs = mapper.runs(from: mapper.attributedString(for: block))
        let linked = runs.first { $0.attributes.link != nil }
        XCTAssertEqual(linked?.text, "here")
        XCTAssertEqual(linked?.attributes.link, "https://x.com")
        XCTAssertEqual(linked?.attributes.underline, false)
        XCTAssertNil(linked?.attributes.foreground)
    }

    func test_runs_fromAttributedString_urlValuedLink_normalizesAndSuppresses() {
        let s = NSAttributedString(string: "tap", attributes: [
            .font: NSFont.systemFont(ofSize: 16),
            .link: URL(string: "https://x.com")!,
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        let back = mapper.runs(from: s).first
        XCTAssertEqual(back?.attributes.link, "https://x.com")
        XCTAssertEqual(back?.attributes.underline, false)
        XCTAssertNil(back?.attributes.foreground)
    }

    func test_link_isBlue_withoutUnderline() {
        let m = AttributedStringMapper()
        let attrs = m.attributes(for: CharacterAttributes(link: "https://x.com"), style: .body)
        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, NSColor.linkColor)
        XCTAssertNil(attrs[.underlineStyle], "links must not be underlined in 6a")
    }
}
#endif
