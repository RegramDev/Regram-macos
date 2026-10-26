import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import MessageUtils
import RegramCore
import RegramServices

func regramSupportsSelectedTranslationProvider(_ message: Message) -> Bool {
    regramSupportsSelectedTranslationProvider(message, cachedData: nil)
}

func regramSupportsSelectedTranslationProvider(_ message: Message, cachedData: CachedPeerData?) -> Bool {
    message.id.peerId.namespace != Namespaces.Peer.SecretChat && !message.containsSecretMedia && !message.isCopyProtected(cachedData: cachedData) && !message.media.contains { $0 is TelegramMediaPaidContent || $0 is TelegramMediaExpiredContent } && !message.attributes.contains { $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute || $0 is RGRevokedMessageAttribute }
}

func regramUsesNativeTranslation(_ message: Message) -> Bool {
    !regramSupportsSelectedTranslationProvider(message)
}

func regramTranslationCacheIdentity(_ identity: String, tone: TranslationTone = .neutral) -> String {
    identity + "\nselected-provider-v2:" + tone.rawValue
}

func regramTranslationMatches(_ message: Message, settings: RegramAccountSettings, tone: TranslationTone = .neutral) -> Bool {
    message.attributes.compactMap { $0 as? RegramTranslationMessageAttribute }.first?.configuration == regramTranslationCacheIdentity(settings.translationIdentity, tone: tone)
}

public func regramQuickTranslationLanguage(_ message: Message, settings: RegramAccountSettings) -> String? {
    guard let stamp = message.attributes.compactMap({ $0 as? RegramTranslationMessageAttribute }).first,
          stamp.configuration == settings.translationIdentity, let language = stamp.quickToLang, !language.isEmpty,
          message.translationAttribute(toLang: language) != nil else { return nil }
    return language
}

private enum RegramTranslationPlanError: Error {
    case invalid
}

private func regramMapRichText(_ value: RichText, depth: Int, transform: (String) throws -> String) throws -> RichText {
    guard depth <= 64 else { throw RegramTranslationPlanError.invalid }
    func map(_ text: RichText) throws -> RichText { try regramMapRichText(text, depth: depth + 1, transform: transform) }
    switch value {
    case let .plain(text): return .plain(try transform(text))
    case let .bold(text): return .bold(try map(text))
    case let .italic(text): return .italic(try map(text))
    case let .underline(text): return .underline(try map(text))
    case let .strikethrough(text): return .strikethrough(try map(text))
    case let .url(text, url, webpageId): return .url(text: try map(text), url: url, webpageId: webpageId)
    case let .concat(texts): return .concat(try texts.map(map))
    case let .subscript(text): return .subscript(try map(text))
    case let .superscript(text): return .superscript(try map(text))
    case let .marked(text): return .marked(try map(text))
    case let .anchor(text, name): return .anchor(text: try map(text), name: name)
    case let .textSpoiler(text): return .textSpoiler(text: try map(text))
    case let .textButton(button): return .textButton(InstantPageButton(text: try map(button.text), action: button.action, color: button.color, isLink: button.isLink))
    case .empty, .fixed, .email, .phone, .image, .formula, .textCustomEmoji, .textAutoEmail, .textAutoPhone, .textAutoUrl, .textBankCard, .textTonAddress, .textBotCommand, .textCashtag, .textHashtag, .textMention, .textMentionName, .textDate:
        return value
    }
}

private func regramMapInstantPageBlock(_ value: InstantPageBlock, depth: Int, transform: (String) throws -> String) throws -> InstantPageBlock {
    guard depth <= 64 else { throw RegramTranslationPlanError.invalid }
    func rich(_ text: RichText) throws -> RichText { try regramMapRichText(text, depth: depth + 1, transform: transform) }
    func block(_ value: InstantPageBlock) throws -> InstantPageBlock { try regramMapInstantPageBlock(value, depth: depth + 1, transform: transform) }
    func caption(_ value: InstantPageCaption) throws -> InstantPageCaption { try InstantPageCaption(text: rich(value.text), credit: rich(value.credit)) }
    switch value {
    case let .title(text): return .title(try rich(text))
    case let .subtitle(text): return .subtitle(try rich(text))
    case let .header(text): return .header(try rich(text))
    case let .subheader(text): return .subheader(try rich(text))
    case let .heading(text, level): return .heading(text: try rich(text), level: level)
    case let .paragraph(text): return .paragraph(try rich(text))
    case let .footer(text): return .footer(try rich(text))
    case let .list(items, ordered): return .list(items: try items.map { item in
        switch item {
        case .unknown: return .unknown
        case let .text(text, number, checked): return .text(try rich(text), number, checked)
        case let .blocks(blocks, number, checked): return .blocks(try blocks.map(block), number, checked)
        }
    }, ordered: ordered)
    case let .blockQuote(blocks, text, collapsed): return .blockQuote(blocks: try blocks.map(block), caption: try rich(text), collapsed: collapsed)
    case let .pullQuote(text, textCaption): return .pullQuote(text: try rich(text), caption: try rich(textCaption))
    case let .image(id, valueCaption, url, webpageId, spoiler): return .image(id: id, caption: try caption(valueCaption), url: url, webpageId: webpageId, spoiler: spoiler)
    case let .video(id, valueCaption, autoplay, loop, spoiler): return .video(id: id, caption: try caption(valueCaption), autoplay: autoplay, loop: loop, spoiler: spoiler)
    case let .audio(id, valueCaption): return .audio(id: id, caption: try caption(valueCaption))
    case let .document(id, valueCaption): return .document(id: id, caption: try caption(valueCaption))
    case let .buttonRow(alignment, buttons): return .buttonRow(alignment: alignment, buttons: try buttons.map { button in InstantPageButton(text: try rich(button.text), action: button.action, color: button.color, isLink: button.isLink) })
    case let .cover(value): return .cover(try block(value))
    case let .webEmbed(url, html, dimensions, valueCaption, stretchToWidth, allowScrolling, coverId): return .webEmbed(url: url, html: html, dimensions: dimensions, caption: try caption(valueCaption), stretchToWidth: stretchToWidth, allowScrolling: allowScrolling, coverId: coverId)
    case let .postEmbed(url, webpageId, avatarId, author, date, blocks, valueCaption): return .postEmbed(url: url, webpageId: webpageId, avatarId: avatarId, author: author, date: date, blocks: try blocks.map(block), caption: try caption(valueCaption))
    case let .collage(items, valueCaption): return .collage(items: try items.map(block), caption: try caption(valueCaption))
    case let .slideshow(items, valueCaption): return .slideshow(items: try items.map(block), caption: try caption(valueCaption))
    case let .kicker(text): return .kicker(try rich(text))
    case let .thinking(text): return .thinking(try rich(text))
    case let .table(title, rows, bordered, striped, compact): return .table(title: try rich(title), rows: try rows.map { row in
        InstantPageTableRow(cells: try row.cells.map { cell in
            InstantPageTableCell(text: try cell.text.map(rich), header: cell.header, alignment: cell.alignment, verticalAlignment: cell.verticalAlignment, colspan: cell.colspan, rowspan: cell.rowspan)
        })
    }, bordered: bordered, striped: striped, compact: compact)
    case let .details(title, blocks, expanded): return .details(title: try rich(title), blocks: try blocks.map(block), expanded: expanded)
    case let .relatedArticles(title, articles): return .relatedArticles(title: try rich(title), articles: try articles.map { article in
        InstantPageRelatedArticle(url: article.url, webpageId: article.webpageId, title: try article.title.map(transform), description: try article.description.map(transform), photoId: article.photoId, author: article.author, date: article.date)
    })
    case let .map(latitude, longitude, zoom, dimensions, valueCaption): return .map(latitude: latitude, longitude: longitude, zoom: zoom, dimensions: dimensions, caption: try caption(valueCaption))
    case .unsupported, .authorDate, .formula, .preformatted, .divider, .anchor, .channelBanner:
        return value
    }
}

struct RegramMessageTranslationPlan {
    struct Text {
        let text: String
        let entities: [MessageTextEntity]
    }
    private enum Content {
        case plain
        case rich(InstantPage)
        case poll(Int, Bool)
    }
    let texts: [Text]
    private let content: Content

    init(message: Message) throws {
        if let rich = message.attributes.compactMap({ $0 as? RichTextMessageAttribute }).first {
            let page = rich.fullInstantPage ?? rich.instantPage
            var texts: [Text] = []
            var length = 0
            _ = try page.blocks.map { block in
                try regramMapInstantPageBlock(block, depth: 0) { text in
                    length += text.utf16.count
                    guard texts.count < 256, length <= 25_000 else { throw RegramTranslationPlanError.invalid }
                    texts.append(Text(text: text, entities: []))
                    return text
                }
            }
            self.texts = texts
            self.content = .rich(page)
        } else if let poll = message.media.compactMap({ $0 as? TelegramMediaPoll }).first {
            var texts = [Text(text: poll.text, entities: poll.textEntities)] + poll.options.map { Text(text: $0.text, entities: $0.entities) }
            if let solution = poll.results.solution { texts.append(Text(text: solution.text, entities: solution.entities)) }
            guard texts.count <= 256, texts.reduce(0, { $0 + $1.text.utf16.count }) <= 25_000 else { throw RegramTranslationPlanError.invalid }
            self.texts = texts
            self.content = .poll(poll.options.count, poll.results.solution != nil)
        } else {
            guard message.text.utf16.count <= 25_000 else { throw RegramTranslationPlanError.invalid }
            self.texts = [Text(text: message.text, entities: message.attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.first?.entities ?? [])]
            self.content = .plain
        }
    }

    var hasContent: Bool {
        texts.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func attribute(translations: [TranslationMessageAttribute.Additional], toLang: String) throws -> TranslationMessageAttribute {
        guard translations.count == texts.count,
              zip(texts, translations).allSatisfy({ source, result in source.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw RegramTranslationPlanError.invalid }
        switch content {
        case .plain:
            guard let first = translations.first else { throw RegramTranslationPlanError.invalid }
            return TranslationMessageAttribute(text: first.text, entities: first.entities, toLang: toLang)
        case let .poll(options, hasSolution):
            return TranslationMessageAttribute(text: translations[0].text, entities: translations[0].entities, additional: Array(translations[1..<(options + 1)]), pollSolution: hasSolution ? translations.last : nil, toLang: toLang)
        case let .rich(page):
            var index = 0
            let blocks = try page.blocks.map { block in
                try regramMapInstantPageBlock(block, depth: 0) { _ in
                    guard index < translations.count else { throw RegramTranslationPlanError.invalid }
                    defer { index += 1 }
                    return translations[index].text
                }
            }
            let translated = InstantPage(blocks: blocks, media: page.media, isComplete: page.isComplete, rtl: page.rtl, url: page.url, views: page.views)
            return TranslationMessageAttribute(text: "", entities: [], toLang: toLang, instantPage: translated)
        }
    }
}

func regramHasSelectedTranslationContent(_ message: Message) -> Bool {
    (try? RegramMessageTranslationPlan(message: message).hasContent) ?? false
}

func regramTranslateMessageBatch(messages: [Message], to: String, isCurrent: @escaping () -> Bool, translate: @escaping (Message, RegramMessageTranslationPlan.Text) -> Signal<TranslationMessageAttribute.Additional, TranslateFetchError>, commit: @escaping (Message, TranslationMessageAttribute) -> Signal<Bool, NoError>) -> Signal<Void, TranslateFetchError> {
    let result = messages.reduce(Signal<Void, TranslateFetchError>.complete()) { previous, message in
        previous |> then(
            deferred { () -> Signal<Void, TranslateFetchError> in
                guard isCurrent() else { return .fail(.outdated) }
                guard let plan = try? RegramMessageTranslationPlan(message: message), plan.hasContent else { return .single(()) }
                let translations = plan.texts.reduce(Signal<[TranslationMessageAttribute.Additional], TranslateFetchError>.single([])) { previous, part in
                    previous |> mapToSignal { values in
                        guard isCurrent() else { return .fail(.outdated) }
                        return translate(message, part) |> take(1) |> map { values + [$0] }
                    }
                }
                return translations |> mapToSignal { results -> Signal<Void, TranslateFetchError> in
                    guard isCurrent() else { return .fail(.outdated) }
                    guard let attribute = try? plan.attribute(translations: results, toLang: to) else { return .fail(.network) }
                    return commit(message, attribute) |> take(1) |> castError(TranslateFetchError.self) |> mapToSignal { applied in
                        applied && isCurrent() ? .single(()) : .fail(.outdated)
                    }
                } |> `catch` { _ in
                    isCurrent() ? .single(()) : .fail(.outdated)
                }
            }
        )
    }
    return result |> filter { _ in false } |> then(deferred { isCurrent() ? .single(()) : .fail(.outdated) })
}

func regramCommitMessageTranslation(transaction: Transaction, original: Message, attribute: TranslationMessageAttribute, context: [String], settings: RegramAccountSettings, configurationIdentity: String, tone: TranslationTone, isCurrent: () -> Bool) -> Bool {
    guard isCurrent(), settings.translationIdentity == configurationIdentity,
          let current = transaction.getMessage(original.id), current.stableVersion == original.stableVersion,
          regramSupportsSelectedTranslationProvider(current, cachedData: transaction.getPeerCachedData(peerId: current.id.peerId)),
          regramLLMTranslationContext(transaction: transaction, message: current, settings: settings) == context else { return false }
    transaction.updateMessage(original.id) { current in
        var attributes = current.attributes.filter { !($0 is TranslationMessageAttribute || $0 is RegramTranslationMessageAttribute) }
        attributes.append(attribute)
        attributes.append(RegramTranslationMessageAttribute(configuration: regramTranslationCacheIdentity(configurationIdentity, tone: tone)))
        return .update(StoreMessage(id: current.id, customStableId: nil, globallyUniqueId: current.globallyUniqueId, groupingKey: current.groupingKey, threadId: current.threadId, timestamp: current.timestamp, flags: StoreMessageFlags(current.flags), tags: current.tags, globalTags: current.globalTags, localTags: current.localTags, forwardInfo: current.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: current.author?.id, text: current.text, attributes: attributes, media: current.media))
    }
    return true
}

func regramTranslateMessages(account: Account, messageIds: [MessageId], to: String, settings: RegramAccountSettings, configurationIdentity: String? = nil, isCurrent: @escaping () -> Bool, tone: TranslationTone = .neutral) -> Signal<Void, TranslateFetchError> {
    let identity = configurationIdentity ?? settings.translationIdentity
    let current: () -> Bool = {
        isCurrent() && RegramPreferences.shared.settings(accountId: account.peerId.toInt64()).translationIdentity == identity
    }
    return account.postbox.transaction { transaction in
        messageIds.compactMap { transaction.getMessage($0) }.filter { message in
            regramSupportsSelectedTranslationProvider(message, cachedData: transaction.getPeerCachedData(peerId: message.id.peerId))
        }.map { message in (message, regramLLMTranslationContext(transaction: transaction, message: message, settings: settings)) }
    }
    |> castError(TranslateFetchError.self)
    |> mapToSignal { messages in
        let contexts = Dictionary(messages.map { ($0.0.id, $0.1) }, uniquingKeysWith: { first, _ in first })
        return regramTranslateMessageBatch(messages: messages.map(\.0), to: to, isCurrent: current, translate: { message, part in
            let context = contexts[message.id] ?? []
            let permission: () -> Signal<Bool, NoError> = {
                account.postbox.transaction { transaction in
                    let currentSettings = RegramPreferences.shared.settings(accountId: account.peerId.toInt64())
                    guard current(), currentSettings.translationIdentity == identity,
                          let current = transaction.getMessage(message.id), current.stableVersion == message.stableVersion,
                          regramSupportsSelectedTranslationProvider(current, cachedData: transaction.getPeerCachedData(peerId: current.id.peerId)),
                          regramLLMTranslationContext(transaction: transaction, message: current, settings: currentSettings) == context else { return false }
                    return true
                }
            }
            let telegramTranslate: (String, String) -> Signal<String, TranslateFetchError> = { text, language in
                TelegramEngine(account: account).messages.translate(text: text, toLang: RegramChatLanguagePolicy.comparisonCode(language), entities: [], tone: tone)
                |> mapError { _ in TranslateFetchError.network }
                |> mapToSignal { result in
                    guard let result else { return .fail(.network) }
                    return .single(result.0)
                }
            }
            let entities = part.entities
            let ranges = entities.enumerated().map { RGTranslationLinkPlan.ProtectedRange(range: NSRange(location: $0.element.range.lowerBound, length: $0.element.range.count), id: $0.offset) }
            let protected = Set(entities.enumerated().compactMap { index, entity -> Int? in
                switch entity.type {
                case .Url, .TextUrl, .Email, .Code, .Pre, .Mention, .TextMention, .Hashtag, .BotCommand, .CustomEmoji, .PhoneNumber, .BankCard, .TonAddress, .FormattedDate: return index
                default: return nil
                }
            })
            return regramProtectedTranslation(text: part.text, to: to, accountId: account.peerId.toInt64(), settings: settings, ranges: ranges, protectedIds: protected, context: context, permitsNetworkFallback: permission, telegramTranslate: telegramTranslate)
            |> map { result in
                let converted = result.ranges.compactMap { range -> MessageTextEntity? in
                    guard range.id >= 0, range.id < entities.count else { return nil }
                    return MessageTextEntity(range: range.range.location..<(range.range.location + range.range.length), type: entities[range.id].type)
                }
                return TranslationMessageAttribute.Additional(text: result.text, entities: converted)
            }
        }, commit: { message, attribute in
            account.postbox.transaction { transaction in
                let currentSettings = RegramPreferences.shared.settings(accountId: account.peerId.toInt64())
                return regramCommitMessageTranslation(transaction: transaction, original: message, attribute: attribute, context: contexts[message.id] ?? [], settings: currentSettings, configurationIdentity: identity, tone: tone, isCurrent: current)
            }
        })
    }
}
