import Cocoa
import Postbox
import TelegramCore
import TelegramContext
import SwiftSignalKit
import AlertsUI
import Localization
import RegramCore
import TGUIKit

private enum RegramStorySaveError: Error {
    case unavailable
}

func regramSaveStoryMedia(context: any AccountContextProtocol, file: TelegramMediaFile, peerId: PeerId, original: EngineStoryItem, isCurrent: @escaping () -> Bool) -> Disposable {
    let cancelled = Atomic(value: false)
    let requests = DisposableSet()
    func validate() -> Signal<Bool, NoError> {
        context.account.postbox.transaction { transaction -> Bool in
            guard !cancelled.with({ $0 }) else { return false }
            let stored = transaction.getStory(id: StoryId(peerId: peerId, id: original.id)) ?? transaction.getStoryItems(peerId: peerId).first(where: { $0.id == original.id })?.value
            let raw: Stories.Item?
            if let item = stored?.get(Stories.StoredItem.self), case let .item(value) = item { raw = value } else { raw = nil }
            guard let raw else { return original.isMy }
            guard raw.timestamp == original.timestamp, let media = raw.media, media.isEqual(to: original.media._asMedia()) else { return false }
            let override = RegramPreferences.shared.settings(accountId: context.peerId.toInt64())["allowDownloadingStories"].bool
            let premium = (transaction.getPeer(context.peerId) as? TelegramUser)?.flags.contains(.isPremium) ?? false
            return original.isMy || override || (!raw.isForwardingDisabled && premium)
        }
    }
    let resource = validate() |> castError(RegramStorySaveError.self) |> deliverOnMainQueue |> mapToSignal { allowed -> Signal<MediaResourceData, RegramStorySaveError> in
        guard allowed, !cancelled.with({ $0 }), isCurrent() else { return .fail(.unavailable) }
        return context.account.postbox.transaction { transaction -> PeerReference? in
            guard let peer = transaction.getPeer(peerId) else { return nil }
            return PeerReference(peer)
        } |> castError(RegramStorySaveError.self) |> deliverOnMainQueue |> mapToSignal { reference in
            Signal { subscriber in
                let operations = DisposableSet()
                let fetch = MetaDisposable()
                operations.add(fetch)
                var fetching = false
                operations.add((context.account.postbox.mediaBox.resourceData(file.resource) |> deliverOnMainQueue).start(next: { data in
                    guard !cancelled.with({ $0 }), isCurrent() else { subscriber.putError(.unavailable); return }
                    if data.complete {
                        subscriber.putNext(data)
                        subscriber.putCompletion()
                    } else if !fetching {
                        fetching = true
                        guard let reference else { subscriber.putError(.unavailable); return }
                        fetch.set(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .peer(peerId), userContentType: .story, reference: .media(media: .story(peer: reference, id: original.id, media: original.media._asMedia()), resource: file.resource), range: nil).start(error: { _ in
                            subscriber.putError(.unavailable)
                        }))
                    }
                }))
                return operations
            }
        }
    } |> timeout(180, queue: .mainQueue(), alternate: .fail(.unavailable))
    requests.add(showModalProgress(signal: resource, for: context.window).start(next: { data in
        guard data.complete, !cancelled.with({ $0 }), isCurrent() else { return }
        requests.add((validate() |> deliverOnMainQueue).start(next: { allowed in
            guard !cancelled.with({ $0 }), isCurrent() else { return }
            guard allowed else { alert(for: context.window, info: strings().unknownError); return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.fileName ?? "Story"
            panel.beginSheetModal(for: context.window) { response in
                guard response == .OK, let destination = panel.url, !cancelled.with({ $0 }) else { return }
                requests.add((validate() |> deliverOnMainQueue).start(next: { allowed in
                    guard !cancelled.with({ $0 }), isCurrent() else { return }
                    guard allowed else { alert(for: context.window, info: strings().unknownError); return }
                    let temporary = destination.deletingLastPathComponent().appendingPathComponent(".regram-story-" + UUID().uuidString)
                    do {
                        try FileManager.default.copyItem(at: URL(fileURLWithPath: data.path), to: temporary)
                        if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary) }
                        else { try FileManager.default.moveItem(at: temporary, to: destination) }
                    } catch {
                        try? FileManager.default.removeItem(at: temporary)
                        alert(for: context.window, info: error.localizedDescription)
                    }
                }))
            }
        }))
    }, error: { _ in
        guard !cancelled.with({ $0 }), isCurrent() else { return }
        alert(for: context.window, info: strings().unknownError)
    }))
    return ActionDisposable { _ = cancelled.swap(true); requests.dispose() }
}
