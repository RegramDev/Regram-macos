import XCTest
import Postbox
import TelegramCore
import ChatHistoryModel
@testable import ChatUI

final class ChatHeaderTranslationStateTests: XCTestCase {
    private func state() -> ChatPresentationInterfaceState.TranslateState {
        return .init(canTranslate: true, translate: false, from: "en", to: "zh-Hans", paywall: false, result: [:])
    }

    func testUnrelatedMessageResultsDoNotChangeHeaderPresentation() {
        let original = state()
        var updated = original
        let id = MessageId(peerId: PeerId(1), namespace: 0, id: 10)
        updated.result[.init(id: id, toLang: "zh-Hans")] = .loading(toLang: "zh-Hans")
        XCTAssertEqual(ChatHeaderState.Translation(original), ChatHeaderState.Translation(updated))
        updated.result[.init(id: id, toLang: "zh-Hans")] = .complete(toLang: "zh-Hans")
        XCTAssertEqual(ChatHeaderState(main: .none, translate: .init(original)), ChatHeaderState(main: .none, translate: .init(updated)))
    }

    func testVisibleTranslationControlsStillChangeHeaderPresentation() {
        let original = state()
        var updated = original
        updated.translate = true
        XCTAssertNotEqual(ChatHeaderState.Translation(original), ChatHeaderState.Translation(updated))
        updated = original
        updated.to = "ja"
        XCTAssertNotEqual(ChatHeaderState.Translation(original), ChatHeaderState.Translation(updated))
        updated = original
        updated.from = "ru"
        XCTAssertNotEqual(ChatHeaderState.Translation(original), ChatHeaderState.Translation(updated))
        updated = original
        updated.paywall = true
        XCTAssertNotEqual(ChatHeaderState.Translation(original), ChatHeaderState.Translation(updated))
        updated = original
        updated.tone = .formal
        XCTAssertNotEqual(ChatHeaderState.Translation(original), ChatHeaderState.Translation(updated))
    }

    func testPinnedMessageTranslationStillChangesHeaderPresentation() {
        let pinned = ChatPinnedMessage(messageId: MessageId(peerId: PeerId(1), namespace: 0, id: 10), message: nil, isLatest: true)
        let loading = ChatHeaderState(main: .pinned(pinned, .loading(toLang: "zh-Hans"), doNotChangeTable: false))
        let complete = ChatHeaderState(main: .pinned(pinned, .complete(toLang: "zh-Hans"), doNotChangeTable: false))
        XCTAssertNotEqual(loading, complete)
    }
}
