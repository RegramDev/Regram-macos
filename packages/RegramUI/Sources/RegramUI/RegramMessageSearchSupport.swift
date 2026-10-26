import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import InputDataUI
import RegramCore
import Localization
import ChatHistoryModel

struct RegramSearchMessageRow: Equatable {
    let messageId: MessageId
    let threadId: Int64?
    let groupPeerId: PeerId
    let title: String
    let preview: String
    let date: String
}

func regramSearchMessageOrder(_ message: Message) -> RegramSearchMessageOrder {
    RegramSearchMessageOrder(timestamp: message.timestamp, peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, messageId: message.id.id)
}

func regramSearchIsGroup(_ peer: Peer) -> Bool {
    if let group = peer as? TelegramGroup { return group.membership == .Member }
    if let channel = peer as? TelegramChannel, case .group = channel.info {
        return channel.participationStatus != .kicked
    }
    return false
}

func regramSearchGroupTitle(_ peer: Peer?, peerId: PeerId, accountId: Int64) -> String {
    RGGroupRemarks.shared.name(accountId: accountId, peerId: peerId.toInt64()) ?? peer?.displayTitle ?? regramString("CommonGroups.Group")
}

private func regramSearchRichText(_ text: RichText, reveal: Bool, depth: Int = 0) -> String {
    guard depth < 64 else { return "" }
    func inner(_ text: RichText) -> String { regramSearchRichText(text, reveal: reveal, depth: depth + 1) }
    switch text {
    case .empty, .image: return ""
    case let .plain(text): return text
    case let .formula(text): return text
    case let .textCustomEmoji(_, alt): return alt
    case let .textSpoiler(text):
        let value = inner(text)
        return reveal ? value : String(repeating: "▪", count: min(64, value.utf16.count))
    case let .concat(texts): return texts.map(inner).joined()
    case let .textButton(button): return inner(button.text)
    case let .bold(text), let .italic(text), let .underline(text), let .strikethrough(text), let .fixed(text), let .subscript(text), let .superscript(text), let .marked(text), let .textAutoEmail(text), let .textAutoPhone(text), let .textAutoUrl(text), let .textBankCard(text), let .textTonAddress(text), let .textBotCommand(text), let .textCashtag(text), let .textHashtag(text), let .textMention(text): return inner(text)
    case let .url(text, _, _), let .email(text, _), let .phone(text, _), let .anchor(text, _), let .textMentionName(text, _), let .textDate(text, _, _): return inner(text)
    }
}

private func regramSearchRichBlocks(_ blocks: [InstantPageBlock], reveal: Bool, depth: Int = 0) -> String {
    guard depth < 64 else { return "" }
    func rich(_ text: RichText) -> String { regramSearchRichText(text, reveal: reveal) }
    func nested(_ blocks: [InstantPageBlock]) -> String { regramSearchRichBlocks(blocks, reveal: reveal, depth: depth + 1) }
    return blocks.prefix(64).map { block -> String in
        switch block {
        case let .title(text), let .subtitle(text), let .header(text), let .subheader(text), let .paragraph(text), let .footer(text), let .kicker(text), let .thinking(text): return rich(text)
        case let .heading(text, _), let .preformatted(text, _), let .authorDate(text, _): return rich(text)
        case let .formula(text): return text
        case let .blockQuote(blocks, caption, _): return nested(blocks) + " " + rich(caption)
        case let .pullQuote(text, caption): return rich(text) + " " + rich(caption)
        case let .cover(block): return nested([block])
        case let .list(items, _): return items.prefix(64).map { item -> String in
            switch item {
            case let .text(text, _, _): return rich(text)
            case let .blocks(blocks, _, _): return nested(blocks)
            case .unknown: return ""
            }
        }.joined(separator: " ")
        case let .table(title, rows, _, _, _): return ([rich(title)] + rows.prefix(16).map { $0.cells.compactMap { $0.text.map(rich) }.joined(separator: " ") }).joined(separator: " ")
        case let .details(title, blocks, _): return rich(title) + " " + nested(blocks)
        case let .collage(blocks, caption), let .slideshow(blocks, caption): return nested(blocks) + " " + rich(caption.text)
        case let .image(_, caption, _, _, _), let .video(_, caption, _, _, _), let .audio(_, caption), let .document(_, caption): return rich(caption.text)
        case let .buttonRow(_, buttons): return buttons.map { rich($0.text) }.joined(separator: " ")
        default: return ""
        }
    }.joined(separator: " ")
}

func regramSearchMessageRow(_ message: Message, group: Peer?, groupPeerId: PeerId, accountId: Int64, dateFormatter: DateFormatter, threadId: Int64? = nil) -> RegramSearchMessageRow {
    let reveal = RegramPreferences.shared.settings(accountId: accountId)["automaticallyRevealSpoilers"].bool
    let text: String
    let spoilers: [Range<Int>]
    if let rich = message.attributes.compactMap({ $0 as? RichTextMessageAttribute }).first {
        text = regramSearchRichBlocks((rich.fullInstantPage ?? rich.instantPage).blocks, reveal: reveal)
        spoilers = []
    } else {
        text = message.text
        spoilers = message.attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.flatMap(\.entities).compactMap { entity in
            if case .Spoiler = entity.type { return entity.range }
            return nil
        }
    }
    let preview = RegramMessageSearchPolicy.preview(text, spoilers: spoilers, reveal: reveal).trimmingCharacters(in: .whitespacesAndNewlines)
    return RegramSearchMessageRow(messageId: message.id, threadId: message.threadId ?? threadId, groupPeerId: groupPeerId, title: regramSearchGroupTitle(group, peerId: groupPeerId, accountId: accountId), preview: preview.isEmpty ? regramString("CommonGroups.Media") : preview, date: dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp))))
}

func regramSearchMessageEntries(_ messages: [RegramSearchMessageRow], context: any AccountContextProtocol, sectionId: Int32, index: inout Int32) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    for (position, message) in messages.enumerated() {
        let id = message.messageId
        let open = { RegramUIHooks.shared.openMessage(context, id, message.threadId) }
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: InputDataIdentifier("search_message_\(id.peerId.toInt64())_\(id.namespace)_\(id.id)"), data: .init(name: message.title + " · " + message.date, color: theme.colors.text, type: .next, viewType: messages.count == 1 ? .singleItem : position == 0 ? .firstItem : position == messages.count - 1 ? .lastItem : .innerItem, description: message.preview, action: open, menuItems: {
            [ContextMenuItem(regramString("CommonGroups.OpenMessage"), handler: open), ContextMenuItem(regramString("CommonGroups.OpenGroup"), handler: { RegramUIHooks.shared.openPeerInfo(context, message.groupPeerId) })]
        })))
        index += 1
    }
    return entries
}

func regramSearchDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: appCurrentLanguage.primaryLanguage.languageCode)
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}
