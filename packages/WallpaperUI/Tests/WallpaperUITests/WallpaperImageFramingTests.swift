import AppKit
import XCTest
import TGUIKit
@testable import WallpaperUI

final class WallpaperImageFramingTests: XCTestCase {
    private func image(size: NSSize) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for (index, color) in [NSColor.red, .green, .blue].enumerated() {
            context.setFillColor(color.cgColor)
            context.fill(NSRect(x: CGFloat(index) * size.width / 3, y: 0, width: size.width / 3, height: size.height))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func pixel(_ image: CGImage, fraction: CGFloat) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: NSRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = (image.height / 2 * image.width + Int(CGFloat(image.width) * fraction)) * 4
        return Array(UnsafeBufferPointer(start: data + offset, count: 4))
    }

    private func assertFraming(size: NSSize, expected: NSSize, file: StaticString = #filePath, line: UInt = #line) throws {
        let input = try image(size: size)
        let output = cropWallpaperImage(input, dimensions: size, rect: size.bounds, magnify: 1, settings: nil)
        XCTAssertEqual(output.width, Int(expected.width), file: file, line: line)
        XCTAssertEqual(output.height, Int(expected.height), file: file, line: line)
        XCTAssertEqual(CGFloat(output.width) / CGFloat(output.height), size.width / size.height, accuracy: 0.002, file: file, line: line)
        for (fraction, channel) in [(CGFloat(0.1), 0), (0.5, 1), (0.9, 2)] {
            let rgba = try pixel(output, fraction: fraction)
            XCTAssertGreaterThan(rgba[channel], 240, file: file, line: line)
            XCTAssertEqual(rgba[3], 255, file: file, line: line)
            for other in 0 ..< 3 where other != channel {
                XCTAssertLessThan(rgba[other], 15, file: file, line: line)
            }
        }
    }

    func testLandscapeKeepsBothEdgesAndOriginalAspectRatio() throws {
        try assertFraming(size: NSSize(width: 1600, height: 900), expected: NSSize(width: 1040, height: 585))
    }

    func testPortraitKeepsBothEdgesAndOriginalAspectRatio() throws {
        try assertFraming(size: NSSize(width: 900, height: 1600), expected: NSSize(width: 889, height: 1580))
    }

    func testSquareKeepsBothEdgesAndOriginalAspectRatio() throws {
        try assertFraming(size: NSSize(width: 1200, height: 1200), expected: NSSize(width: 1040, height: 1040))
    }

    func testSmallImageIsNotUpscaledWhenAppliedAgain() throws {
        try assertFraming(size: NSSize(width: 320, height: 180), expected: NSSize(width: 320, height: 180))
    }
}
