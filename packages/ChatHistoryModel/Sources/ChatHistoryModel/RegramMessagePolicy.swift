import Foundation
import Postbox
import TelegramCore
import MessageTextUtils
import RegramCore

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
    return RegramPreferences.shared.filter(accountId: accountId).shouldHide(text: regramMessageText(message), peerId: peerId, authorId: message.author?.id.toInt64(), incoming: !message.flags.intersection(.IsIncomingMask).isEmpty)
}
