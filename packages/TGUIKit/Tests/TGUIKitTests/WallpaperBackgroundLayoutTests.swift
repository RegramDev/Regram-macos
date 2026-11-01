import AppKit
import XCTest
@testable import TGUIKit

final class WallpaperBackgroundLayoutTests: XCTestCase {
    private var windows: [Window] = []

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    override func tearDown() {
        for window in windows {
            window.contentView?.subviews.removeAll()
            window.orderOut(nil)
        }
        windows.removeAll()
        super.tearDown()
    }

    private func makeView(size: NSSize, imageSize: NSSize, scale: CGFloat = 1, colors: [NSColor]? = nil) throws -> BackgroundView {
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(imageSize.width * scale), height: Int(imageSize.height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: imageSize)
        let view = BackgroundView(frame: size.bounds)
        let window = Window(contentRect: size.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        try XCTUnwrap(window.contentView).addSubview(view)
        windows.append(window)
        view.backgroundMode = .background(image: image, intensity: nil, colors: colors, rotation: nil, metadata: nil)
        view.updateLayout(size: size, transition: .immediate)
        return view
    }

    private func imageLayers(_ layer: CALayer) -> [CALayer] {
        return (layer.contents == nil ? [] : [layer]) + (layer.sublayers ?? []).flatMap(imageLayers)
    }

    private func imageFrame(_ view: BackgroundView) throws -> NSRect {
        var identifiers = Set<ObjectIdentifier>()
        func layers(in view: NSView) -> [CALayer] {
            return (view.layer.map(imageLayers) ?? []) + view.subviews.flatMap { layers(in: $0) }
        }
        let layers = layers(in: view).filter { identifiers.insert(ObjectIdentifier($0)).inserted }
        XCTAssertEqual(layers.count, 1)
        return try XCTUnwrap(layers.first).frame
    }

    func testShortPhotoUsesActualChatHeightAtBothBackingScales() throws {
        for scale: CGFloat in [1, 2] {
            let view = try makeView(size: NSSize(width: 320, height: 200), imageSize: NSSize(width: 1000, height: 500), scale: scale)
            XCTAssertEqual(try imageFrame(view), NSRect(x: -40, y: 0, width: 400, height: 200))
        }
    }

    func testWidePhotoFillsWidthWithoutExtraZoom() throws {
        let view = try makeView(size: NSSize(width: 800, height: 300), imageSize: NSSize(width: 1600, height: 900))
        XCTAssertEqual(try imageFrame(view), NSRect(x: 0, y: -75, width: 800, height: 450))
    }

    func testPortraitPhotoKeepsCenteredAspectFill() throws {
        let view = try makeView(size: NSSize(width: 300, height: 600), imageSize: NSSize(width: 800, height: 1600))
        XCTAssertEqual(try imageFrame(view), NSRect(x: 0, y: 0, width: 300, height: 600))
    }

    func testResizingChatRecomputesPhotoFrame() throws {
        let view = try makeView(size: NSSize(width: 320, height: 200), imageSize: NSSize(width: 1000, height: 500))
        let size = NSSize(width: 400, height: 600)
        view.setFrameSize(size)
        view.updateLayout(size: size, transition: .immediate)
        XCTAssertEqual(try imageFrame(view), NSRect(x: -400, y: 0, width: 1200, height: 600))
    }

    func testPatternRetainsItsMinimumHeight() throws {
        let view = try makeView(size: NSSize(width: 320, height: 200), imageSize: NSSize(width: 400, height: 800), colors: [.red])
        XCTAssertEqual(try imageFrame(view), NSRect(x: 0, y: -70, width: 320, height: 640))
    }
}
