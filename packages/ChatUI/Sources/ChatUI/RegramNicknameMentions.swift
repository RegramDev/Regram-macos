import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import TelegramContext
import TelegramUtils
import InputView
import SwiftSignalKit
import RegramCore

func regramNicknameMentionText(peer: Peer, suffix: String, enabled: Bool) -> NSAttributedString? {
    guard enabled, let user = peer as? TelegramUser else { return nil }
    let fullName = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    let title = fullName.isEmpty ? peer.compactDisplayTitle : fullName
    guard !title.isEmpty else { return nil }
    let text = NSMutableAttributedString(string: title, attributes: [TextInputAttributes.textMention: ChatTextInputTextMentionAttribute(peerId: peer.id)])
    text.append(NSAttributedString(string: suffix))
    return text
}

final class RegramNicknameMentionInputResolver {
    private let context: any AccountContextProtocol
    private let disposable = MetaDisposable()
    private var generation: UInt64 = 0

    init(context: any AccountContextProtocol) { self.context = context }
    deinit { disposable.dispose() }

    func cancel() {
        generation &+= 1
        disposable.set(nil)
    }

    func update(input: ChatTextInputState, canApply: @escaping () -> Bool, apply: @escaping (ChatTextInputState) -> Void) {
        cancel()
        let accountId = context.peerId.toInt64()
        guard RegramPreferences.shared.settings(accountId: accountId)["mentionAsUserIdLink"].bool, input.selectionRange.isEmpty else { return }
        let detected = generateTextEntities(input.inputText, enabledTypes: .all)
        let mentionRanges = detected.compactMap { entity -> Range<Int>? in if case .Mention = entity.type { return entity.range }; return nil }
        let excluded = (detected + input.messageTextEntities([])).compactMap { entity -> Range<Int>? in
            switch entity.type {
            case .Code, .Pre, .Url, .Email, .TextUrl, .TextMention, .CustomEmoji, .BotCommand: return entity.range
            default: return nil
            }
        }
        let candidates = RegramNicknameMentionPolicy.candidates(text: input.inputText, mentionRanges: mentionRanges, excludedRanges: excluded, selection: input.selectionRange)
        var names: [String] = []
        for candidate in candidates where !names.contains(candidate.username) {
            if names.count < RegramNicknameMentionPolicy.maximumResolvedUsernames { names.append(candidate.username) }
        }
        guard !names.isEmpty else { return }
        let token = generation
        let lookup = Signal<Void, NoError>.single(()) |> delay(RegramNicknameMentionPolicy.lookupDelay, queue: .mainQueue()) |> mapToSignal { [context] _ -> Signal<[(String, EnginePeer?)], NoError> in
            combineLatest(names.map { name in
                context.engine.peers.resolvePeerByName(name: name, referrer: nil, ageLimit: 10) |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
                    if case let .result(peer) = result { return .single(peer) }
                    return .complete()
                } |> take(1) |> timeout(RegramNicknameMentionPolicy.lookupTimeout, queue: .mainQueue(), alternate: .single(nil)) |> map { (name, $0) }
            })
        }
        disposable.set((lookup |> deliverOnMainQueue).start(next: { [weak self] values in
            guard let self, self.generation == token, RegramPreferences.shared.settings(accountId: accountId)["mentionAsUserIdLink"].bool, canApply() else { return }
            var peers: [String: Peer] = [:]
            for (name, peer) in values {
                guard case let .user(user)? = peer else { continue }
                let aliases = user.usernames.map { $0.username.lowercased() } + [user.username?.lowercased()].compactMap { $0 }
                guard aliases.contains(name) else { continue }
                peers[name] = user
            }
            let original = input.attributedString()
            let updated = NSMutableAttributedString(attributedString: original)
            var changes: [RegramNicknameMentionPolicy.Replacement] = []
            for candidate in candidates.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
                guard let peer = peers[candidate.username], let nickname = regramNicknameMentionText(peer: peer, suffix: "", enabled: true) else { continue }
                let replacement = NSMutableAttributedString(attributedString: nickname)
                if candidate.range.upperBound == original.length, input.selectionRange.lowerBound == original.length { replacement.append(NSAttributedString(string: " ")) }
                let inherited = original.attributes(at: candidate.range.lowerBound, effectiveRange: nil)
                for key in [TextInputAttributes.bold, TextInputAttributes.italic, TextInputAttributes.underline, TextInputAttributes.strikethrough, TextInputAttributes.spoiler] {
                    if let value = inherited[key] { replacement.addAttribute(key, value: value, range: NSRange(location: 0, length: replacement.length)) }
                }
                updated.replaceCharacters(in: NSRange(location: candidate.range.lowerBound, length: candidate.range.count), with: replacement)
                changes.append(.init(range: candidate.range, text: replacement.string))
            }
            guard !changes.isEmpty else { return }
            apply(ChatTextInputState(attributedText: updated, selectionRange: RegramNicknameMentionPolicy.remap(input.selectionRange, replacements: changes)))
        }))
    }
}
