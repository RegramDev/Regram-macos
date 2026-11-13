import Foundation
import Postbox
import RegramServices
import SwiftSignalKit
import TelegramCore

private func regramTranslationBlocks(text: String, entities: [MessageTextEntity], maxLength: Int) -> [(String, [MessageTextEntity])] {
    var offset = 0
    return gtranslateSplitTextBySentences(text, maxChunkLength: maxLength).map { chunk in
        let start = offset
        offset += chunk.utf16.count
        let chunkEntities = entities.compactMap { entity -> MessageTextEntity? in
            let lower = max(start, entity.range.lowerBound)
            let upper = min(offset, entity.range.upperBound)
            guard lower < upper else { return nil }
            return MessageTextEntity(range: (lower - start)..<(upper - start), type: entity.type)
        }
        return (chunk, chunkEntities)
    }
}

public func regramJoinTranslationBlocks(_ parts: [(String, [MessageTextEntity])], source: [String]) -> (String, [MessageTextEntity]) {
    if parts.count == 1, let part = parts.first { return part }
    var text = ""
    var entities: [MessageTextEntity] = []
    var offset = 0
    for (part, original) in zip(parts, source) {
        if original.allSatisfy(\.isWhitespace) {
            text += original
            entities += part.1.map { entity in
                MessageTextEntity(range: (offset + entity.range.lowerBound)..<(offset + entity.range.upperBound), type: entity.type)
            }
            offset += original.utf16.count
            continue
        }
        let leading = original.prefix(while: \.isWhitespace)
        let trailing = String(original.reversed().prefix(while: \.isWhitespace).reversed())
        let body = part.0.drop(while: \.isWhitespace)
        let end = body.lastIndex { !$0.isWhitespace }.map { body.index(after: $0) } ?? body.startIndex
        let translated = body[..<end]
        let start = part.0[..<body.startIndex].utf16.count
        let length = translated.utf16.count
        offset += leading.utf16.count
        entities += part.1.compactMap { entity in
            let lower = max(start, entity.range.lowerBound)
            let upper = min(start + length, entity.range.upperBound)
            guard lower < upper else { return nil }
            return MessageTextEntity(range: (offset + lower - start)..<(offset + upper - start), type: entity.type)
        }
        text += String(leading) + String(translated) + trailing
        offset += length + trailing.utf16.count
    }
    return (text, entities)
}

public func regramTranslateTelegramText(engine: TelegramEngine, text: String, to: String, entities: [MessageTextEntity] = [], tone: TranslationTone = .neutral, messageId: MessageId? = nil, permitsTextRetry: Bool = true) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    let target = RegramChatLanguagePolicy.targetCode(to)
    return regramTranslateTelegramText(text: text, entities: entities, messageId: messageId, permitsTextRetry: permitsTextRetry) { text, entities, messageId in
        engine.messages.translate(text: text, toLang: target, entities: entities, tone: tone, messageId: messageId)
    }
}

func regramTranslateTelegramText(text: String, entities: [MessageTextEntity], messageId: MessageId?, permitsTextRetry: Bool = true, request: @escaping (String, [MessageTextEntity], MessageId?) -> Signal<(String, [MessageTextEntity])?, TranslationError>) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    return request(text, entities, messageId)
    |> `catch` { error -> Signal<(String, [MessageTextEntity])?, TranslationError> in
        guard permitsTextRetry, case .textTooLong = error else { return .fail(error) }
        let blocks = regramTranslationBlocks(text: text, entities: entities, maxLength: min(1024, max(1, text.utf16.count / 2)))
        guard blocks.count > 1 else { return .fail(error) }
        let signals = blocks.map { block -> Signal<(String, [MessageTextEntity]), TranslationError> in
            if block.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .single(block) }
            return deferred { request(block.0, block.1, nil) }
            |> mapToSignal { result in
                guard let result, !result.0.allSatisfy(\.isWhitespace) else { return .fail(.generic) }
                return .single(result)
            }
        }
        return regramTranslateSequentially(signals, chunkTimeout: 45, failure: .generic)
        |> map { parts in
            regramJoinTranslationBlocks(parts, source: blocks.map(\.0))
        }
    }
}
