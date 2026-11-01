#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class MapperTests: XCTestCase {
    private let mapper = AttributedStringMapper()

    func test_characterAttributes_roundTripThroughDict() {
        let ca = CharacterAttributes(bold: true, italic: true, underline: true, strikethrough: true,
                                     fontSize: 18, foreground: .black,
                                     highlight: RGBAColor(red: 1, green: 1, blue: 0),
                                     baselineOffset: 4)
        let dict = mapper.attributes(for: ca, style: .body)
        let back = mapper.characterAttributes(from: dict)
        XCTAssertTrue(back.bold); XCTAssertTrue(back.italic)
        XCTAssertTrue(back.underline); XCTAssertTrue(back.strikethrough)
        XCTAssertNil(back.foreground)
        XCTAssertEqual(back.baselineOffset ?? 0, 4, accuracy: 0.01)
        XCTAssertNotNil(back.highlight)
    }

    func test_paragraphBlock_roundTripsRuns() {
        let block = ParagraphBlock(id: BlockID("p1"), style: .body, runs: [
            TextRun(text: "Plain "),
            TextRun(text: "bold", attributes: CharacterAttributes(bold: true)),
        ])
        let attr = mapper.attributedString(for: block)
        XCTAssertEqual(attr.string, "Plain bold")
        let runs = mapper.runs(from: attr)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].text, "Plain ")
        XCTAssertFalse(runs[0].attributes.bold)
        XCTAssertEqual(runs[1].text, "bold")
        XCTAssertTrue(runs[1].attributes.bold)
    }

    func test_serifHeadingFont_doesNotReadBackAsFontFamily() {
        let m = AttributedStringMapper()
        // .heading1 resolves to the system serif (New York); a default CharacterAttributes has no fontFamily.
        let attrs = m.attributes(for: CharacterAttributes(), style: .heading1)
        let ca = m.characterAttributes(from: attrs)
        XCTAssertNil(ca.fontFamily, "serif heading font is style-derived and must not leak into the model as a user fontFamily")
    }

    func test_inlineCode_rendersMonospace_andRoundTripsClean() {
        let ca = CharacterAttributes(inlineCode: true)
        let dict = mapper.attributes(for: ca, style: .body)
        let font = dict[.font] as? NSFont
        XCTAssertNotNil(font)
        XCTAssertNotEqual(font?.fontName, NSFont.systemFont(ofSize: 16).fontName,
                          "inline code must render with a non-system (monospace) font")
        let back = mapper.characterAttributes(from: dict)
        XCTAssertTrue(back.inlineCode)
        XCTAssertNil(back.fontFamily, "the mono font name must not leak into fontFamily")
        XCTAssertNil(back.highlight, "the code background must not be read back as a highlight")
        XCTAssertNil(back.fontSize, "a plain inline-code run must not pin a font size")
        XCTAssertFalse(back.bold, "monospaced .regular carries no bold trait")
        XCTAssertFalse(back.italic, "monospaced .regular carries no italic trait")
        XCTAssertEqual((dict[.font] as? NSFont)?.pointSize, 14, "body inline code renders at the body base size")
    }
}
#endif
