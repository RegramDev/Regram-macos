import XCTest
import AppKit
@testable import RegramServices

final class RegramBrandingAssetsTests: XCTestCase {
    func testBundledSourceArtworkAndAdditionalFontCatalogHaveExactChoices() {
        XCTAssertEqual(RegramBranding.icons.count, 9)
        for name in RegramBranding.icons {
            XCTAssertNotNil(RegramBranding.image(name, dark: false), name)
            XCTAssertNotNil(RegramBranding.image(name, dark: true), name)
        }
        XCTAssertEqual(RegramFontStore.downloadableFonts.map(\.id), ["AnthropicSans", "AnthropicSerif", "GoogleSans", "GoogleSansFlex", "GoogleSansCode"])
        XCTAssertEqual(RegramFontStore.downloadableFonts.map(\.group), ["Anthropic", "Anthropic", "Google", "Google", "Google"])
        XCTAssertEqual(RegramFonts.latinFamilies.count, 13)
        XCTAssertEqual(RegramFonts.chineseFamilies.count, 3)
    }

    func testNativeApplicationIconsHavePaddingMaskAndAllDockRepresentations() throws {
        XCTAssertEqual(RegramBranding.icons, ["RGConversation", "RGAzure", "RGIris", "RGMint", "RGGathering", "RGAmber", "RGNebula", "RGJade", "RGClassic"])
        for dark in [false, true] {
            var renderedChoices = Set<Data>()
            for name in RegramBranding.icons {
                let icon = try XCTUnwrap(RegramBranding.applicationIcon(name, dark: dark))
                XCTAssertEqual(Set(icon.representations.map(\.pixelsWide)), [16, 32, 64, 128, 256, 512, 1024])
                let rendered = try XCTUnwrap(RegramBranding.renderedIcon(name, dark: dark, pixelSize: 128))
                var pixels = Data(count: 128 * 128 * 4)
                try pixels.withUnsafeMutableBytes { buffer in
                    let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 128 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                    context.draw(rendered, in: CGRect(x: 0, y: 0, width: 128, height: 128))
                }
                func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * 128 + x) * 4 + 3] }
                for corner in [(0, 0), (127, 0), (0, 127), (127, 127), (14, 14), (113, 113)] { XCTAssertEqual(alpha(corner.0, corner.1), 0, name) }
                XCTAssertEqual(alpha(11, 64), 0, name)
                XCTAssertEqual(alpha(116, 64), 0, name)
                XCTAssertGreaterThan(alpha(20, 64), 250, name)
                XCTAssertGreaterThan(alpha(64, 64), 250, name)
                renderedChoices.insert(pixels)
            }
            XCTAssertEqual(renderedChoices.count, 9)
        }
        XCTAssertNil(RegramBranding.applicationIcon("Default.icns", dark: false))
    }
}
