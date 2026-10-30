import AppKit
import RegramCore
import ImageIO
import XCTest
@testable import RegramServices

final class RegramClipboardImagesTests: XCTestCase {
    private func image(width: Int = 3001, height: Int = 97) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 3, y: 2, width: width - 6, height: height - 4))
        return try XCTUnwrap(context.makeImage())
    }

    private func bytes(_ image: CGImage, type: String) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testPNGAndTIFFOriginalBytesArePreservedExactly() throws {
        for type in ["public.png", "public.tiff"] {
            let original = try bytes(image(), type: type)
            let source = try XCTUnwrap(RegramClipboardImages.imageBytes(original))
            XCTAssertEqual(source.data, original)
            XCTAssertEqual(source.type, type)
            let url = try RegramClipboardImages.temporaryFile(source)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            XCTAssertEqual(try Data(contentsOf: url), original)
            let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let result = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
            XCTAssertEqual(result.width, 3001)
            XCTAssertEqual(result.height, 97)
            XCTAssertTrue([CGImageAlphaInfo.premultipliedLast, .premultipliedFirst, .last, .first].contains(result.alphaInfo))
        }
    }

    func testImageFilesRouteToPhotoPreviewWithoutChangingTheURL() throws {
        let source = try XCTUnwrap(RegramClipboardImages.imageBytes(bytes(image(), type: "public.png")))
        let url = try RegramClipboardImages.temporaryFile(source)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let plan = RegramClipboardImages.snapshot(urls: [url])
        XCTAssertEqual(plan.urls, [url])
        XCTAssertTrue(plan.asMedia)
        XCTAssertTrue(plan.containsImage)
    }

    func testFallbackNSImageUsesTheLargestBitmapAndLosslessPNG() throws {
        let full = try image(width: 1600, height: 800)
        let small = try image(width: 160, height: 80)
        let value = NSImage(size: NSSize(width: 160, height: 80))
        value.addRepresentation(NSBitmapImageRep(cgImage: small))
        value.addRepresentation(NSBitmapImageRep(cgImage: full))
        let encoded = try XCTUnwrap(RegramClipboardImages.losslessPNG(value))
        XCTAssertEqual(encoded.type, "public.png")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(encoded.data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 1600)
        XCTAssertEqual(decoded.height, 800)
    }

    func testPreparedClipboardPhotosKeepOriginalBytesAndUseTheNativeHighestQualityPolicy() throws {
        let original = try bytes(image(), type: "public.png")
        let source = try XCTUnwrap(RegramClipboardImages.imageBytes(original))
        let url = try RegramClipboardImages.temporaryFile(source)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let prepared = try RegramClipboardImages.preparingPhotos(RegramClipboardImages.snapshot(urls: [url]))
        let photo = try XCTUnwrap(prepared.urls.first)
        defer { try? FileManager.default.removeItem(at: photo.deletingLastPathComponent()) }
        XCTAssertTrue(prepared.asMedia)
        XCTAssertNotEqual(photo, url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: photo), original)
        XCTAssertTrue(RGMediaPolicy.isPastedPhoto(path: photo.path))
        var settings = RegramAccountSettings()
        settings["outgoingPhotoQuality"] = .integer(20)
        XCTAssertEqual(RGMediaPolicy.photoQuality(settings: settings), 0.2)
        XCTAssertEqual(RGMediaPolicy.photoQuality(settings: settings, pasted: true), 1)
        XCTAssertEqual(RGMediaPolicy.photoMaximumDimension(native: 1280, settings: settings, pasted: true), 2560)
    }

    func testInvalidBytesCannotBecomeAnOriginalImage() {
        XCTAssertNil(RegramClipboardImages.imageBytes(Data("not an image".utf8)))
        XCTAssertNil(RegramClipboardImages.imageBytes(Data()))
    }

    func testPreparedStandardPhotosPreserveBytesWithoutEnablingHighestQuality() throws {
        let original = try bytes(image(width: 640, height: 480), type: "public.png")
        let input = try RegramClipboardImages.temporaryFile(XCTUnwrap(RegramClipboardImages.imageBytes(original)))
        var directories = Set([input.deletingLastPathComponent()])
        defer { for directory in directories { try? FileManager.default.removeItem(at: directory) } }
        var settings = RegramAccountSettings()
        settings["outgoingPhotoQuality"] = .integer(20)
        var snapshot = RegramClipboardImages.snapshot(urls: [input])
        for highestQuality in [false, true, false] {
            snapshot = try RegramClipboardImages.preparingPhotos(snapshot, originalQuality: highestQuality)
            let photo = try XCTUnwrap(snapshot.urls.first)
            directories.insert(photo.deletingLastPathComponent())
            XCTAssertTrue(RegramClipboardImages.isPreparedPhoto(path: photo.path))
            XCTAssertTrue(RegramClipboardImages.canSendAsPhoto(photo))
            XCTAssertEqual(RGMediaPolicy.isPastedPhoto(path: photo.path), highestQuality)
            XCTAssertEqual(try Data(contentsOf: photo), original)
            XCTAssertEqual(RGMediaPolicy.photoQuality(settings: settings, pasted: RGMediaPolicy.isPastedPhoto(path: photo.path)), highestQuality ? 1 : 0.2)
            XCTAssertEqual(RGMediaPolicy.photoMaximumDimension(native: 1280, settings: settings, pasted: RGMediaPolicy.isPastedPhoto(path: photo.path)), highestQuality ? 2560 : 1280)
            let repeated = try RegramClipboardImages.preparingPhotos(snapshot, originalQuality: highestQuality)
            XCTAssertEqual(repeated.urls, snapshot.urls)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
        XCTAssertFalse(RegramClipboardImages.isPreparedPhoto(path: input.path))
    }

    func testPreparingMixedContentKeepsDocumentsAndPhotoDimensionLimits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RegramClipboardMixed." + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directories = Set([directory])
        defer { for directory in directories { try? FileManager.default.removeItem(at: directory) } }
        let document = directory.appendingPathComponent("Document.txt")
        try Data("Synthetic clipboard document".utf8).write(to: document)
        XCTAssertFalse(RegramClipboardImages.snapshot(urls: [document]).containsImage)
        XCTAssertEqual(try RegramClipboardImages.preparingPhotos(RegramClipboardImages.snapshot(urls: [document])).urls, [document])
        for (width, height, eligible) in [(640, 480, true), (3001, 97, false), (32, 32, false)] {
            let path = directory.appendingPathComponent("Image-\(width).download")
            let data = try bytes(image(width: width, height: height), type: "public.png")
            try data.write(to: path)
            for highestQuality in [false, true] {
                let prepared = try RegramClipboardImages.preparingPhotos(RegramClipboardImages.snapshot(urls: [document, path]), originalQuality: highestQuality)
                XCTAssertEqual(prepared.urls.first, document)
                let photo = try XCTUnwrap(prepared.urls.last)
                directories.insert(photo.deletingLastPathComponent())
                XCTAssertEqual(photo.pathExtension, "png")
                XCTAssertEqual(try Data(contentsOf: photo), data)
                XCTAssertEqual(RegramClipboardImages.canSendAsPhoto(photo), eligible)
            }
        }
    }

    func testClipboardPhotosRespectTelegramPhotoDimensions() throws {
        for (width, height, photo) in [(640, 480, true), (480, 640, true), (3001, 97, false), (32, 32, false)] {
            let source = try XCTUnwrap(RegramClipboardImages.imageBytes(bytes(image(width: width, height: height), type: "public.png")))
            let url = try RegramClipboardImages.temporaryFile(source)
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            XCTAssertEqual(RegramClipboardImages.canSendAsPhoto(url), photo)
        }
        XCTAssertFalse(RegramClipboardImages.canSendAsPhoto(URL(fileURLWithPath: "/missing-image.png")))
    }
}
