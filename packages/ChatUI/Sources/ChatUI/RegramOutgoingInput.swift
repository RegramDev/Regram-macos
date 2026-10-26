import Foundation
import Postbox
import TelegramCore
import TelegramContext
import InputView
import RegramCore

private func regramPanguInput(_ input: ChatTextInputState) -> ChatTextInputState {
    let protected = input.messageTextEntities().compactMap { entity -> Range<Int>? in
        switch entity.type {
        case .Code, .Pre, .TextUrl, .TextMention, .Mention, .CustomEmoji, .BlockQuote: return entity.range
        default: return nil
        }
    }
    let transformed = RGFeaturePangu.transform(input.makeAttributeString(), protectedUtf16Ranges: protected)
    return ChatTextInputState(attributedText: transformed, selectionRange: transformed.length..<transformed.length)
}

public func regramEditingInput(_ input: ChatTextInputState, context: any AccountContextProtocol) -> ChatTextInputState {
    guard RegramPreferences.shared.settings(accountId: context.peerId.toInt64())["features.enablePanguOnEditing"].bool else { return input }
    return regramPanguInput(input)
}

public func regramReceivingText(_ text: NSAttributedString, accountId: Int64) -> NSAttributedString {
    guard RegramPreferences.shared.settings(accountId: accountId)["features.enablePanguOnReceiving"].bool else { return text }
    return RGFeaturePangu.transform(text)
}

public func regramOutgoingInput(_ input: ChatTextInputState, context: any AccountContextProtocol, peerId: PeerId) -> ChatTextInputState {
    let accountId = context.peerId.toInt64()
    let settings = RegramPreferences.shared.settings(accountId: accountId)
    let preferences = settings.chatPreferences(accountId: accountId, peerId: peerId.toInt64())
    var result = input
    if preferences.panguSpacing ?? settings["panguSpacing"].bool {
        result = regramPanguInput(input)
    }
    let format = preferences.formatting ?? settings["defaultOutgoingFormatting"].string
    guard format != "none", !result.inputText.isEmpty else { return result }
    let length = result.inputText.utf16.count
    let protected = result.messageTextEntities().map(\.range).sorted { $0.lowerBound < $1.lowerBound }
    var ranges: [Range<Int>] = []
    var offset = 0
    for range in protected {
        if range.lowerBound > offset { ranges.append(offset..<min(length, range.lowerBound)) }
        offset = max(offset, range.upperBound)
    }
    if offset < length { ranges.append(offset..<length) }
    var attributes = result.attributes
    for range in ranges where !range.isEmpty {
        switch format {
        case "bold": attributes.append(.bold(range))
        case "italic": attributes.append(.italic(range))
        case "underline": attributes.append(.underline(range))
        case "strikethrough": attributes.append(.strikethrough(range))
        case "spoiler": attributes.append(.spoiler(range))
        default: break
        }
    }
    return ChatTextInputState(inputText: result.inputText, selectionRange: result.selectionRange, attributes: attributes)
}
