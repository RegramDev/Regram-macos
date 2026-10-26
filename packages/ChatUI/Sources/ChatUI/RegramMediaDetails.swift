import Cocoa
import AVFoundation
import ImageIO
import Postbox
import TelegramCore
import TelegramContext
import TelegramTheme
import TelegramMediaUtils
import TelegramUtils
import InputDataUI
import TGUIKit
import FilePanels
import Localization
import RegramCore
import SwiftSignalKit

private func mediaDetailsTitle(_ key: String) -> String {
    regramLocalizedString(key, languageCode: appCurrentLanguage.primaryLanguage.languageCode)
}

private struct RegramMediaDetail: Codable, Equatable {
    let field: String
    let value: String
    let source: String
}

private struct RegramMediaDetailsRequest {
    var values: [RegramMediaDetail] = []
    var path: String?

    init(message: Message, context: any AccountContextProtocol) {
        if let image = message.media.compactMap({ $0 as? TelegramMediaImage }).first,
           let representation = image.representations.max(by: { Int64($0.dimensions.width) * Int64($0.dimensions.height) < Int64($1.dimensions.width) * Int64($1.dimensions.height) }) {
            values.append(.init(field: "resolution", value: "\(representation.dimensions.width) × \(representation.dimensions.height)", source: "declared"))
            if let size = representation.resource.size { values.append(.init(field: "size", value: "\(size)", source: "declared")) }
            path = context.account.postbox.mediaBox.completedResourcePath(representation.resource)
        } else if let file = message.media.compactMap({ $0 as? TelegramMediaFile }).first {
            values.append(.init(field: "format", value: file.mimeType, source: "declared"))
            if let size = file.size { values.append(.init(field: "size", value: "\(size)", source: "declared")) }
            if let dimensions = file.dimensions { values.append(.init(field: "resolution", value: "\(dimensions.width) × \(dimensions.height)", source: "declared")) }
            for attribute in file.attributes {
                switch attribute {
                case let .Video(duration, _, _, _, _, codec):
                    values.append(.init(field: "duration", value: String(format: "%.3f", duration), source: "declared"))
                    if let codec { values.append(.init(field: "codec", value: codec, source: "declared")) }
                case let .Audio(_, duration, _, _, _):
                    values.append(.init(field: "duration", value: String(duration), source: "declared"))
                default:
                    break
                }
            }
            path = context.account.postbox.mediaBox.completedResourcePath(file.resource)
        }
    }

    func read() -> [RegramMediaDetail] {
        var result = values
        guard let path else {
            result.append(.init(field: "cache", value: "notDownloaded", source: "status"))
            for field in ["resolution", "format", "codec", "bitRate", "frameRate", "duration", "size"] where !result.contains(where: { $0.field == field }) {
                result.append(.init(field: field, value: "unknown", source: "status"))
            }
            return result
        }
        result.append(.init(field: "cache", value: "downloaded", source: "status"))
        let url = URL(fileURLWithPath: path)
        if let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber {
            result.append(.init(field: "size", value: size.stringValue, source: "local"))
        }
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if let width = properties[kCGImagePropertyPixelWidth] as? NSNumber, let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
                result.append(.init(field: "resolution", value: "\(width) × \(height)", source: "local"))
            }
            if let type = CGImageSourceGetType(source) { result.append(.init(field: "format", value: type as String, source: "local")) }
        } else {
            let asset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(asset.duration)
            if duration.isFinite, duration > 0 { result.append(.init(field: "duration", value: String(format: "%.3f", duration), source: "local")) }
            for track in asset.tracks {
                if track.mediaType == .video {
                    let dimensions = track.naturalSize.applying(track.preferredTransform)
                    if abs(dimensions.width) > 0, abs(dimensions.height) > 0 {
                        result.append(.init(field: "resolution", value: "\(Int(abs(dimensions.width))) × \(Int(abs(dimensions.height)))", source: "local"))
                    }
                    if track.nominalFrameRate > 0 { result.append(.init(field: "frameRate", value: String(format: "%.3f", track.nominalFrameRate), source: "local")) }
                }
                if track.estimatedDataRate > 0 { result.append(.init(field: "bitRate", value: String(format: "%.0f", track.estimatedDataRate), source: "local")) }
                for description in track.formatDescriptions {
                    let value = CMFormatDescriptionGetMediaSubType(description as! CMFormatDescription)
                    let bytes = [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
                    if let code = String(bytes: bytes, encoding: .ascii), !code.trimmingCharacters(in: .whitespaces).isEmpty {
                        result.append(.init(field: "codec", value: code, source: "local"))
                    }
                }
            }
        }
        for field in ["resolution", "format", "codec", "bitRate", "frameRate", "duration", "size"] where !result.contains(where: { $0.field == field }) {
            result.append(.init(field: field, value: "unknown", source: "status"))
        }
        return result
    }
}

private func mediaDetailsValue(_ detail: RegramMediaDetail) -> String {
    if detail.source == "status" { return mediaDetailsTitle("mediaDetails." + detail.value) }
    return detail.value + " · " + mediaDetailsTitle("mediaDetails.source." + detail.source)
}

func RegramMediaDetailsController(context: any AccountContextProtocol, message: Message) -> InputDataController {
    let request = RegramMediaDetailsRequest(message: message, context: context)
    let read: Signal<[RegramMediaDetail], NoError> = Signal { subscriber in
        subscriber.putNext(request.read())
        subscriber.putCompletion()
        return EmptyDisposable
    } |> runOn(Queue.concurrentDefaultQueue())
    let signal = read |> deliverOnPrepareQueue |> map { values -> InputDataSignalValue in
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = (try? encoder.encode(values)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        var entries: [InputDataEntry] = [.sectionId(0, type: .normal)]
        for (index, detail) in values.enumerated() {
            entries.append(.general(sectionId: 1, index: Int32(index), value: .none, error: nil, identifier: InputDataIdentifier("media_detail_\(index)"), data: .init(name: mediaDetailsTitle("mediaDetails.field." + detail.field), color: theme.colors.text, type: .context(mediaDetailsValue(detail)), viewType: .singleItem, action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(mediaDetailsValue(detail), forType: .string)
            })))
        }
        entries.append(.sectionId(2, type: .normal))
        entries.append(.desc(sectionId: 3, index: 0, text: .plain(mediaDetailsTitle("mediaDetails.notice")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        entries.append(.general(sectionId: 3, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("media_details_copy"), data: .init(name: mediaDetailsTitle("mediaDetails.copy"), color: theme.colors.accent, type: .none, viewType: .firstItem, action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
        })))
        entries.append(.general(sectionId: 3, index: 2, value: .none, error: nil, identifier: InputDataIdentifier("media_details_export"), data: .init(name: mediaDetailsTitle("mediaDetails.export"), color: theme.colors.accent, type: .none, viewType: .lastItem, action: {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Regram-Media-\(UUID().uuidString).json")
            do {
                try Data(json.utf8).write(to: url, options: .atomic)
                savePanel(file: url.path, ext: "json", for: context.window, defaultName: "Regram-Media-Details.json", completion: { _ in try? FileManager.default.removeItem(at: url) })
            } catch {
                NSSound.beep()
            }
        })))
        return InputDataSignalValue(entries: entries)
    }
    return InputDataController(dataSignal: signal, title: mediaDetailsTitle("mediaDetails.title"), hasDone: false)
}

func regramMessageWebURL(_ message: Message) -> URL? {
    func valid(_ value: String) -> URL? {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    for media in message.media {
        if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content, let url = valid(content.url) { return url }
    }
    for attribute in message.attributes {
        if let entities = attribute as? TextEntitiesMessageAttribute {
            for entity in entities.entities {
                if case let .TextUrl(value) = entity.type, let url = valid(value) { return url }
            }
        }
    }
    let range = NSRange(message.text.startIndex..., in: message.text)
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        return detector.matches(in: message.text, range: range).compactMap { $0.url.flatMap { valid($0.absoluteString) } }.first
    }
    return nil
}
