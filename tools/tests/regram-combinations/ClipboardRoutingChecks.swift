import Cocoa
import TGUIKit
import Postbox
import RegramCore
import TelegramTheme
import TelegramMediaUtils
import SwiftSignalKit
import ImageIO
import libwebp

let fixtureSuite = "RegramClipboardRoutingChecks." + UUID().uuidString
let fixtureDefaults = UserDefaults(suiteName: fixtureSuite)!
let fixturePreferences = RegramPreferences(defaults: fixtureDefaults)
let fixtureTemporaryDirectory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("fixture-temporary", isDirectory: true)
let fixtureWindow = Window(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
struct ClipboardFixtureContext { let peerId = PeerId(283392); let account = 0 }
struct ClipboardFixturePeer {}
enum ClipboardFixturePermission { case banSendMedia }
struct ClipboardFixtureEdit { let canEditMedia = true }
struct ClipboardFixtureInterface { var editState: ClipboardFixtureEdit? }
struct ClipboardFixturePresentation { let peer: ClipboardFixturePeer? = nil; var interfaceState = ClipboardFixtureInterface() }
final class ClipboardFixtureInteraction {
    let interactionContext = ClipboardFixtureContext()
    let peerId = PeerId(283392)
    var presentation = ClipboardFixturePresentation()
    var preview: (urls: [URL], asMedia: Bool)?
    func beginMediaReplacement() -> Int { preconditionFailure("Unexpected media replacement") }
    func applyMediaReplacement(_ media: Int, request: Int) { preconditionFailure("Unexpected media replacement") }
    func showPreviewSender(_ urls: [URL], _ asMedia: Bool, _ caption: String?) { preview = (urls, asMedia) }
}
enum ClipboardFixtureSender {
    static func generateMedia(for container: MediaSenderContainer, account: Int, isSecretRelated: Bool) -> Signal<(Int, Int), NoError> { preconditionFailure("No media generation or sends in this fixture") }
}
func fixturePermissionText(from peer: ClipboardFixturePeer, for permission: ClipboardFixturePermission) -> String? { nil }
func fixtureSizeAllowed(context: ClipboardFixtureContext, fileSize: Int64) -> Bool { fileSize < 50 * 1024 * 1024 }
func fixtureFileLimit(context: ClipboardFixtureContext, fileSize: Int64?) { preconditionFailure("Unexpected file limit") }
func fixtureAlert(for window: Window, info: String) { preconditionFailure("Unexpected alert: " + info) }

@main
struct ClipboardRoutingChecks {
    static var checks = 0
    static var failures: [String] = []
    static var temporaryURLs = Set<URL>()
    static func check(_ value: Bool, _ name: String) {
        checks += 1
        if !value { failures.append(name); print("FAIL " + name) }
    }
    static func image(_ width: Int = 640, _ height: Int = 480) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
    static func encoded(_ image: CGImage, type: String, dpi: Int = 72) -> Data? {
        if type == "org.webmproject.webp" {
            let rgba = Array(repeating: UInt8(128), count: image.width * image.height * 4)
            var output: UnsafeMutablePointer<UInt8>?
            let count = rgba.withUnsafeBufferPointer { WebPEncodeLosslessRGBA($0.baseAddress!, Int32(image.width), Int32(image.height), Int32(image.width * 4), &output) }
            guard count > 0, let output else { return nil }
            defer { WebPFree(output) }
            return Data(bytes: output, count: count)
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
    static func main() throws {
        UITestBootstrap.install()
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let inputs = output.appendingPathComponent("synthetic-images", isDirectory: true)
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixtureTemporaryDirectory, withIntermediateDirectories: true)
        defer {
            fixtureDefaults.removePersistentDomain(forName: fixtureSuite)
            try? FileManager.default.removeItem(at: fixtureTemporaryDirectory)
            for url in temporaryURLs {
                if url.deletingLastPathComponent().lastPathComponent.hasPrefix("regram-clipboard-") { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                else if url.lastPathComponent.hasPrefix(RGMediaPolicy.pastedPhotoFilenamePrefix) { try? FileManager.default.removeItem(at: url) }
            }
        }
        for type in ["public.png", "public.jpeg", "public.tiff", "public.heic", "public.avif", "org.webmproject.webp"] {
            for dpi in type == "org.webmproject.webp" ? [72] : [72, 144, 1200] {
                guard let data = encoded(image(), type: type, dpi: dpi), let bytes = RegramClipboardImages.imageBytes(data) else { continue }
                for suffix in [bytes.fileExtension, "download"] {
                    let path = inputs.appendingPathComponent(type + "-\(dpi)." + suffix)
                    try data.write(to: path)
                    for original in [false, true] {
                        for representation in ["bytes", "file", "both"] {
                            let board = NSPasteboard(name: .init("RegramClipboardRoute." + UUID().uuidString))
                            defer { board.releaseGlobally() }
                            let item = NSPasteboardItem()
                            if representation != "bytes" { item.setString(path.absoluteString, forType: .fileURL) }
                            if representation != "file" { item.setData(data, forType: .init(type)) }
                            board.writeObjects([item])
                            fixturePreferences.update(accountId: 283392) { $0["clipboardOriginalImages"] = .bool(original) }
                            let interaction = ClipboardFixtureInteraction()
                            let result = InputPasteboardParser.proccess(pasteboard: board, chatInteraction: interaction, window: fixtureWindow)
                            let deadline = Date().addingTimeInterval(3)
                            while interaction.preview == nil && Date() < deadline { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
                            let label = "\(type)/\(dpi)/\(suffix)/original=\(original)/\(representation)"
                            check(!result && interaction.preview != nil, label + " reaches image preview")
                            if let preview = interaction.preview {
                                let options = ClipboardPreviewClassifier().cachedSenderOptions(preview.urls)
                                check(preview.asMedia && options == [.media], label + " defaults to photo, options=\(options)")
                                check(preview.urls.allSatisfy { RGMediaPolicy.isPastedPhoto(path: $0.path) == original && RegramClipboardImages.isPreparedPhoto(path: $0.path) }, label + " preserves the chosen quality policy")
                                check(preview.urls.allSatisfy { !clipboardWebPUsesDocumentBranch(mimeType: MIMEType($0.path), path: $0.path) }, label + " prepared WebP stays on the image generation branch")
                                for url in preview.urls where !url.path.hasPrefix(inputs.path) { temporaryURLs.insert(url) }
                            }
                            var additional: [URL]?
                            _ = InputPasteboardParser.getPasteboardUrls(board, context: ClipboardFixtureContext()).start(next: { additional = $0 })
                            check(additional.map { ClipboardPreviewClassifier().cachedSenderOptions($0) == [.media] } == true, label + " additional paste keeps photo classification")
                            for url in additional ?? [] where !url.path.hasPrefix(inputs.path) { temporaryURLs.insert(url) }
                        }
                    }
                }
            }
        }
        let document = inputs.appendingPathComponent("Document.txt")
        try Data("Synthetic clipboard document".utf8).write(to: document)
        let picture = inputs.appendingPathComponent("Ordinary.download")
        try encoded(image(), type: "public.png")!.write(to: picture)
        for original in [false, true] {
            for urls in [[document], [document, picture]] {
                let board = NSPasteboard(name: .init("RegramClipboardRoute." + UUID().uuidString))
                defer { board.releaseGlobally() }
                board.writeObjects(urls.map { $0 as NSURL })
                fixturePreferences.update(accountId: 283392) { $0["clipboardOriginalImages"] = .bool(original) }
                let interaction = ClipboardFixtureInteraction()
                _ = InputPasteboardParser.proccess(pasteboard: board, chatInteraction: interaction, window: fixtureWindow)
                check(interaction.preview?.urls.first == document && interaction.preview?.urls.count == urls.count, "Document/mixed paste preserves original document and attachment count")
            }
            for (width, height) in [(32, 32), (3001, 97)] {
                let board = NSPasteboard(name: .init("RegramClipboardRoute." + UUID().uuidString))
                defer { board.releaseGlobally() }
                board.setData(encoded(image(width, height), type: "public.png"), forType: .png)
                let interaction = ClipboardFixtureInteraction()
                _ = InputPasteboardParser.proccess(pasteboard: board, chatInteraction: interaction, window: fixtureWindow)
                check(interaction.preview.map { ClipboardPreviewClassifier().cachedSenderOptions($0.urls) == [.file] } == true, "Small and very narrow images retain native document fallback")
            }
        }
        let report: [String: Any] = ["checks": checks, "failures": failures, "messagesSent": 0, "generalPasteboardUsed": false, "realAccountsUsed": false]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("report.json"))
        print("Clipboard routing checks: \(checks), failures: \(failures.count)")
        if !failures.isEmpty { exit(1) }
    }
}
