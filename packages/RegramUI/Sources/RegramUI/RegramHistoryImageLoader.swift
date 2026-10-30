import AppKit
import SwiftSignalKit

private let regramHistoryImageQueue = Queue(name: "regram.history.images", qos: .utility)

func regramPrepareHistoryImages(_ load: @escaping () -> [Int: Data], shouldLoad: @escaping () -> Bool) -> Signal<[Int: NSImage], NoError> {
    Signal { subscriber in
        var images: [Int: NSImage] = [:]
        if shouldLoad() {
            for (index, data) in load() {
                guard shouldLoad() else { break }
                if let image = NSImage(data: data) { images[index] = image }
            }
        }
        subscriber.putNext(images)
        subscriber.putCompletion()
        return EmptyDisposable
    } |> runOn(regramHistoryImageQueue)
}

func regramLoadHistoryImage(path: String, maximumBytes: Int, shouldLoad: @escaping () -> Bool) -> Signal<(Data, NSImage)?, NoError> {
    Signal { subscriber in
        guard shouldLoad(), maximumBytes > 0,
              let size = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumBytes,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
              data.count <= maximumBytes, shouldLoad(), let image = NSImage(data: data) else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        subscriber.putNext((data, image))
        subscriber.putCompletion()
        return EmptyDisposable
    } |> runOn(regramHistoryImageQueue)
}
