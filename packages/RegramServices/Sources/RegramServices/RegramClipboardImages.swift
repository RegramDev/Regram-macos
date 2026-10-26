import AppKit
import RegramCore
import ImageIO
import UniformTypeIdentifiers

public enum RegramClipboardImages {
    public struct ImageBytes {
        public let data: Data
        public let type: String
        public let fileExtension: String
    }

    public struct Snapshot {
        public let urls: [URL]
        public let containsImage: Bool
        public var asMedia: Bool { true }
    }

    public static func imageBytes(_ data: Data) -> ImageBytes? {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0, let type = CGImageSourceGetType(source) else { return nil }
        let ext: String
        if #available(macOS 11.0, *), let value = UTType(type as String)?.preferredFilenameExtension { ext = value }
        else { ext = ["public.png": "png", "public.jpeg": "jpg", "public.tiff": "tiff", "com.compuserve.gif": "gif", "public.heic": "heic", "public.heif": "heif", "org.webmproject.webp": "webp"][type as String] ?? "image" }
        return ImageBytes(data: data, type: type as String, fileExtension: ext)
    }

    public static func losslessPNG(_ image: NSImage) -> ImageBytes? {
        let bitmap = image.representations.compactMap { $0 as? NSBitmapImageRep }.max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        guard let cgImage = bitmap?.cgImage ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return imageBytes(data as Data)
    }

    public static func temporaryFile(_ image: ImageBytes) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("regram-clipboard-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Image." + image.fileExtension)
        do { try image.data.write(to: url, options: .atomic) }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
        return url
    }

    public static func snapshot(urls: [URL]) -> Snapshot {
        Snapshot(urls: urls, containsImage: urls.contains { CGImageSourceCreateWithURL($0 as CFURL, nil) != nil })
    }

    public static func preparingPhotos(_ snapshot: Snapshot) throws -> Snapshot {
        var urls: [URL] = []
        for url in snapshot.urls {
            if CGImageSourceCreateWithURL(url as CFURL, nil) != nil {
                if RGMediaPolicy.isPastedPhoto(path: url.path) { urls.append(url); continue }
                let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
                guard let image = imageBytes(bytes) else { throw CocoaError(.fileReadCorruptFile) }
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("regram-clipboard-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let target = directory.appendingPathComponent(RGMediaPolicy.pastedPhotoFilenamePrefix + "Image." + image.fileExtension)
                do { try bytes.write(to: target, options: .atomic) }
                catch { try? FileManager.default.removeItem(at: directory); throw error }
                urls.append(target)
            } else { urls.append(url) }
        }
        return Snapshot(urls: urls, containsImage: snapshot.containsImage)
    }

    public static func snapshot(from pasteboard: NSPasteboard) -> Snapshot? {
        let items = pasteboard.pasteboardItems ?? []
        if items.first?.types.contains(.init("com.microsoft.appbundleid")) == true { return nil }
        let files = items.compactMap { $0.string(forType: .fileURL).flatMap(URL.init(string:)) }.filter { $0.isFileURL }
        if !files.isEmpty { return snapshot(urls: files) }
        var urls: [URL] = []
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff, .init("public.jpeg"), .init("public.heic"), .init("public.heif"), .init("org.webmproject.webp"), .init("com.compuserve.gif")]
        for item in items {
            for type in types {
                if let data = item.data(forType: type), let bytes = imageBytes(data), let url = try? temporaryFile(bytes) { urls.append(url); break }
            }
        }
        if !urls.isEmpty { return Snapshot(urls: urls, containsImage: true) }
        guard let image = (pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first,
              !image.representations.contains(where: { $0 is NSPDFImageRep }), let bytes = losslessPNG(image), let url = try? temporaryFile(bytes) else { return nil }
        return Snapshot(urls: [url], containsImage: true)
    }

    @discardableResult public static func copyOriginalImage(path: String, to pasteboard: NSPasteboard) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe), let bytes = imageBytes(data), let url = try? temporaryFile(bytes) else { return false }
        let item = NSPasteboardItem()
        guard item.setString(url.absoluteString, forType: .fileURL), item.setData(bytes.data, forType: .init(bytes.type)) else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
