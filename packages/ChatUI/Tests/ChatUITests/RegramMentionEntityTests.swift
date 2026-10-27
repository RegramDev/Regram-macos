import AppKit
import Postbox
import TelegramCore
import InputView
import TGUIKit
import XCTest

final class RegramMentionEntityTests: XCTestCase {
    func testUserIdSurvivesAttributedInputDraftAndOutgoingEntities() throws {
        for id: Int64 in [1, 4_294_967_295, 4_294_967_296, 8_559_682_245, 9_000_000_000] {
            let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id))
            let text = NSAttributedString(string: "测试用户", attributes: [TextInputAttributes.textMention: ChatTextInputTextMentionAttribute(peerId: peerId)])
            let state = ChatTextInputState(attributedText: text, selectionRange: 4..<4)
            let saved = try JSONDecoder().decode(ChatTextInputState.self, from: JSONEncoder().encode(state))
            for input in [state, saved, ChatTextInputState(attributedText: saved.attributedString(), selectionRange: 4..<4)] {
                let entity = try XCTUnwrap(input.messageTextEntities([]).first)
                guard case let .TextMention(sentId) = entity.type else { return XCTFail("Missing user mention") }
                XCTAssertEqual(sentId, peerId)
                let attribute = try XCTUnwrap(input.attributedString().attribute(TextInputAttributes.textMention, at: 0, effectiveRange: nil) as? ChatTextInputTextMentionAttribute)
                XCTAssertEqual(attribute.peerId, peerId)
            }
        }
    }
}
