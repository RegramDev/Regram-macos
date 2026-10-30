import Foundation
import AppKit
import Speech
import Postbox
import TelegramCore
import SwiftSignalKit
import RegramCore
import RegramServices

func regramCanTranscribe(_ message: Message, settings: RegramAccountSettings) -> Bool {
    ["apple", "openAICompatible"].contains(settings["transcriptionBackend"].string) && message.id.namespace == Namespaces.Message.Cloud && message.id.peerId.namespace != Namespaces.Peer.SecretChat && !message.containsSecretMedia && !message.isCopyProtected() && !message.attributes.contains(where: { $0 is AutoclearTimeoutMessageAttribute })
}

private func regramDownloadAudio(account: Account, message: Message, file: TelegramMediaFile) -> Signal<String, RGTranscriptionError> {
    Signal { subscriber in
        let disposables = DisposableSet()
        let reference = MediaResourceReference.media(media: .message(message: MessageReference(message), media: file), resource: file.resource)
        disposables.add(fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .peer(message.id.peerId), userContentType: .audio, reference: reference).start())
        disposables.add((account.postbox.mediaBox.resourceData(file.resource) |> filter { $0.complete } |> take(1)).start(next: { data in
            subscriber.putNext(data.path)
            subscriber.putCompletion()
        }))
        return disposables
    } |> timeout(90, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.download))
}

private func regramAppleTranscription(url: URL, language: String) -> Signal<String, RGTranscriptionError> {
    requestSpeechRecognitionPermission() |> castError(RGTranscriptionError.self) |> mapToSignal { granted in
        guard granted else { return .fail(.configuration("Speech recognition permission is required.")) }
        return Signal { subscriber in
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: getGTranslateLang(language))), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
                subscriber.putError(.configuration("On-device speech recognition is unavailable for this language."))
                return EmptyDisposable
            }
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty { subscriber.putError(.noSpeech) }
                    else { subscriber.putNext(text); subscriber.putCompletion() }
                } else if error != nil { subscriber.putError(.noSpeech) }
            }
            return ActionDisposable { task.cancel(); withExtendedLifetime(recognizer) {} }
        }
    }
}

private final class RegramTranscriptionLifecycle {
    static let shared = RegramTranscriptionLifecycle()
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in RegramTranscriptionTasks.shared.suspend() })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in RegramTranscriptionTasks.shared.resume() })
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

func regramTranscriptionTaskKey(accountId: Int64, messageId: MessageId) -> RegramTranscriptionTaskKey {
    RegramTranscriptionTaskKey(accountId: accountId, messageId: RGBookmarkMessageId(peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, id: messageId.id))
}

func regramTranscribeMessage(account: Account, message: Message, settings: RegramAccountSettings, language: String) -> Signal<Void, RGTranscriptionError> {
    _ = RegramTranscriptionLifecycle.shared
    let accountId = account.peerId.toInt64()
    let messageId = message.id
    let resourceId = message.media.compactMap { $0 as? TelegramMediaFile }.first(where: { $0.isVoice || $0.isInstantVideo })?.resource.id
    return RegramTranscriptionTasks.shared.perform(key: regramTranscriptionTaskKey(accountId: accountId, messageId: messageId), revision: Int64(message.stableVersion), threadId: message.threadId) { [weak account] isCurrent in
        guard let account, isCurrent() else { return .fail(.cancelled) }
        return account.postbox.transaction { transaction -> Message? in
            if let cached = transaction.getPeerCachedData(peerId: messageId.peerId) as? CachedUserData, cached.flags.contains(.copyProtectionEnabled) || cached.flags.contains(.myCopyProtectionEnabled) { return nil }
            return transaction.getMessage(messageId)
        }
        |> castError(RGTranscriptionError.self)
        |> mapToSignal { current in
            guard let current, isCurrent(), let resourceId, current.media.compactMap({ $0 as? TelegramMediaFile }).contains(where: { ($0.isVoice || $0.isInstantVideo) && $0.resource.id == resourceId }) else { return .fail(.cancelled) }
            let currentSettings = RegramPreferences.shared.settings(accountId: accountId)
            return regramPerformTranscription(account: account, message: current, settings: currentSettings, language: language, isCurrent: isCurrent)
        }
    }
}

private func regramPerformTranscription(account: Account, message: Message, settings: RegramAccountSettings, language: String, isCurrent: @escaping () -> Bool) -> Signal<Void, RGTranscriptionError> {
    guard regramCanTranscribe(message, settings: settings), let file = message.media.compactMap({ $0 as? TelegramMediaFile }).first(where: { $0.isVoice || $0.isInstantVideo }) else { return .fail(.invalidAudio) }
    let accountId = account.peerId.toInt64()
    let external = settings["transcriptionBackend"].string == "openAICompatible"
    let configuration: RGSTTConfiguration?
    do { configuration = external ? try regramSTTConfiguration(accountId: accountId, settings: settings) : nil }
    catch { return .fail(.configuration(error.localizedDescription)) }
    return regramDownloadAudio(account: account, message: message, file: file)
    |> mapToSignal { path in rgPrepareTranscriptionAudio(path: path) }
    |> mapToSignal { audio -> Signal<String, RGTranscriptionError> in
        let recognition = configuration.map { RGOpenAITranscriptionProvider.transcribe(configuration: $0, audioURL: audio.url) } ?? regramAppleTranscription(url: audio.url, language: language)
        return recognition |> afterDisposed { withExtendedLifetime(audio) {} }
    }
    |> timeout(180, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.timeout))
    |> mapToSignal { text in
        account.postbox.transaction { transaction -> Bool in
            if let cached = transaction.getPeerCachedData(peerId: message.id.peerId) as? CachedUserData, cached.flags.contains(.copyProtectionEnabled) || cached.flags.contains(.myCopyProtectionEnabled) { return false }
            var applied = false
            transaction.updateMessage(message.id) { current in
                let currentSettings = RegramPreferences.shared.settings(accountId: accountId)
                guard isCurrent(), current.stableVersion == message.stableVersion, currentSettings.hasSameTranscriptionConfiguration(as: settings) else { return .skip }
                var attributes = current.attributes.filter { !($0 is AudioTranscriptionMessageAttribute) }
                attributes.append(AudioTranscriptionMessageAttribute(id: 0, text: text, isPending: false, didRate: true, error: nil, source: external ? .external : .local))
                applied = true
                return .update(StoreMessage(id: current.id, customStableId: nil, globallyUniqueId: current.globallyUniqueId, groupingKey: current.groupingKey, threadId: current.threadId, timestamp: current.timestamp, flags: StoreMessageFlags(current.flags), tags: current.tags, globalTags: current.globalTags, localTags: current.localTags, forwardInfo: current.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: current.author?.id, text: current.text, attributes: attributes, media: current.media))
            }
            return applied
        } |> castError(RGTranscriptionError.self) |> mapToSignal { $0 ? .single(()) : .fail(.cancelled) }
    }
}
