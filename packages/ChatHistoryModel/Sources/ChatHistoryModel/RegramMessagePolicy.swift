import Foundation
import Postbox
import TelegramCore
import MessageTextUtils
import RegramCore

public struct RegramMessageFilterPayload: Equatable {
    private struct RichPage {
        let page: InstantPage
        let blocks: [InstantPageBlock]
    }
    private let messageId: MessageId
    private let version: UInt32
    private let text: String
    private let authorId: PeerId?
    private let incoming: Bool
    private let richPages: [RichPage]

    fileprivate struct CacheIdentity {
        private final class WeakPage {
            weak var page: InstantPage?
            init(_ page: InstantPage) { self.page = page }
        }
        private let text: String
        private let authorId: PeerId?
        private let incoming: Bool
        private let pages: [WeakPage]
        let cost: Int

        init(_ payload: RegramMessageFilterPayload) {
            text = payload.text
            authorId = payload.authorId
            incoming = payload.incoming
            pages = payload.richPages.map { WeakPage($0.page) }
            cost = text.utf8.count + pages.count * 48 + 128
        }

        func matches(_ payload: RegramMessageFilterPayload) -> Bool {
            guard text == payload.text, authorId == payload.authorId, incoming == payload.incoming, pages.count == payload.richPages.count else { return false }
            return zip(pages, payload.richPages).allSatisfy { previous, current in
                guard let page = previous.page else { return false }
                return page === current.page || page.blocks == current.blocks
            }
        }
    }

    public init(_ message: Message) {
        messageId = message.id
        version = message.stableVersion
        text = message.text
        authorId = message.author?.id
        incoming = !message.flags.intersection(.IsIncomingMask).isEmpty
        richPages = message.attributes.compactMap { attribute in
            guard let rich = attribute as? RichTextMessageAttribute else { return nil }
            let page = rich.fullInstantPage ?? rich.instantPage
            return RichPage(page: page, blocks: page.blocks)
        }
    }

    fileprivate func filterText() -> String {
        var result = text
        for page in richPages { result += "\n" + regramBlockText(page.blocks) }
        return result
    }

    public func shouldHide(accountId: Int64, filter: RegramFilterSnapshot, revision: Int64) -> Bool {
        guard incoming, !filter.isEmpty else { return false }
        let key = RegramMessageVisibilityCache.Key(accountId: accountId, messageId: messageId)
        if let hidden = RegramMessageVisibilityCache.shared.value(key, version: version, revision: revision, payload: self) { return hidden }
        let hidden = filter.shouldHide(peerId: messageId.peerId.toInt64(), authorId: authorId?.toInt64(), incoming: true, text: { filterText() })
        RegramMessageVisibilityCache.shared.store(hidden, key: key, version: version, revision: revision, payload: self)
        return hidden
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.messageId == rhs.messageId, lhs.version == rhs.version, lhs.text == rhs.text, lhs.authorId == rhs.authorId, lhs.incoming == rhs.incoming, lhs.richPages.count == rhs.richPages.count else { return false }
        return zip(lhs.richPages, rhs.richPages).allSatisfy { $0.page === $1.page || $0.blocks == $1.blocks }
    }
}

private final class RegramMessageVisibilityCache {
    struct Key: Hashable {
        let accountId: Int64
        let messageId: MessageId
    }
    struct Value {
        let version: UInt32
        let revision: Int64
        let payload: RegramMessageFilterPayload.CacheIdentity
        let hidden: Bool
    }
    static let shared = RegramMessageVisibilityCache()
    private let lock = NSLock()
    private var values: [Key: Value] = [:]
    private var cost = 0
    private var evictionKeys: [Key] = []
    private var evictionOffset = 0

    func value(_ key: Key, version: UInt32, revision: Int64, payload: RegramMessageFilterPayload) -> Bool? {
        lock.lock()
        let value = values[key]
        lock.unlock()
        guard let value, value.version == version, value.revision == revision, value.payload.matches(payload) else { return nil }
        return value.hidden
    }

    func store(_ hidden: Bool, key: Key, version: UInt32, revision: Int64, payload: RegramMessageFilterPayload) {
        let identity = RegramMessageFilterPayload.CacheIdentity(payload)
        guard identity.cost <= 64 * 1024 else { return }
        var removed: [Value] = []
        lock.lock()
        let isNew = values[key] == nil
        while (isNew && values.count >= 4096) || cost - (values[key]?.payload.cost ?? 0) + identity.cost > 4 * 1024 * 1024 {
            guard evictionOffset < evictionKeys.count else { break }
            let victim = evictionKeys[evictionOffset]
            evictionOffset += 1
            if victim == key {
                evictionKeys.append(victim)
            } else if let value = values.removeValue(forKey: victim) {
                cost -= value.payload.cost
                removed.append(value)
            }
        }
        let previous = values.updateValue(Value(version: version, revision: revision, payload: identity, hidden: hidden), forKey: key)
        if isNew { evictionKeys.append(key) }
        if evictionOffset > 512, evictionOffset * 2 > evictionKeys.count {
            evictionKeys.removeFirst(evictionOffset)
            evictionOffset = 0
        }
        cost += identity.cost - (previous?.payload.cost ?? 0)
        lock.unlock()
        withExtendedLifetime(removed) {}
        withExtendedLifetime(previous) {}
    }
}

private func regramBlockText(_ blocks: [InstantPageBlock], depth: Int = 0) -> String {
    guard depth < 64 else { return "" }
    return blocks.map { block -> String in
        switch block {
        case let .title(text), let .subtitle(text), let .header(text), let .subheader(text), let .paragraph(text), let .footer(text), let .kicker(text), let .thinking(text): return text.plainText
        case let .heading(text, _), let .preformatted(text, _), let .authorDate(text, _): return text.plainText
        case let .formula(latex): return latex
        case let .blockQuote(inner, caption, _): return regramBlockText(inner, depth: depth + 1) + "\n" + caption.plainText
        case let .pullQuote(text, caption): return text.plainText + "\n" + caption.plainText
        case let .cover(inner): return regramBlockText([inner], depth: depth + 1)
        case let .list(items, _):
            return items.map { item -> String in
                switch item {
                case let .text(text, _, _): return text.plainText
                case let .blocks(inner, _, _): return regramBlockText(inner, depth: depth + 1)
                case .unknown: return ""
                }
            }.joined(separator: "\n")
        case let .table(title, rows, _, _, _): return ([title.plainText] + rows.map { $0.cells.compactMap { $0.text?.plainText }.joined(separator: "\t") }).joined(separator: "\n")
        case let .details(title, inner, _): return title.plainText + "\n" + regramBlockText(inner, depth: depth + 1)
        case let .collage(inner, caption), let .slideshow(inner, caption): return regramBlockText(inner, depth: depth + 1) + "\n" + caption.text.plainText + "\n" + caption.credit.plainText
        case let .image(_, caption, _, _, _), let .video(_, caption, _, _, _), let .audio(_, caption), let .document(_, caption): return caption.text.plainText + "\n" + caption.credit.plainText
        case let .buttonRow(_, buttons): return buttons.map { $0.text.plainText }.joined(separator: " ")
        default: return ""
        }
    }.joined(separator: "\n")
}

public func regramMessageText(_ message: Message) -> String {
    var text = message.text
    for attribute in message.attributes {
        if let rich = attribute as? RichTextMessageAttribute { text += "\n" + regramBlockText((rich.fullInstantPage ?? rich.instantPage).blocks) }
    }
    return text
}

public func regramShouldHideMessage(_ message: Message, accountId: Int64, temporaryReveal: Bool = true) -> Bool {
    let peerId = message.id.peerId.toInt64()
    if temporaryReveal, RegramTemporaryReveal.shared.isRevealed(accountId: accountId, peerId: peerId) { return false }
    guard !message.flags.intersection(.IsIncomingMask).isEmpty else { return false }
    let captured = RegramPreferences.shared.captureFilter(accountId: accountId)
    return regramShouldHideMessage(message, accountId: accountId, filter: captured.filter, revision: captured.revision)
}

public func regramShouldHideMessage(_ message: Message, accountId: Int64, filter: RegramFilterSnapshot, revision: Int64) -> Bool {
    guard !message.flags.intersection(.IsIncomingMask).isEmpty else { return false }
    guard !filter.isEmpty else { return false }
    let payload = RegramMessageFilterPayload(message)
    return payload.shouldHide(accountId: accountId, filter: filter, revision: revision)
}
