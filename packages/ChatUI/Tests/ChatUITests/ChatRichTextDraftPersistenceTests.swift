import Foundation
import XCTest
import Postbox
import TelegramCore
@testable import ChatUI

final class ChatRichTextDraftPersistenceTests: XCTestCase {
    func testDraftRoundTripPreservesFormattedUnicodeAndNestedBlocks() throws {
        let page = InstantPage(blocks: [
            .title(.plain("中文 Article 草稿")),
            .paragraph(.concat([.bold(.plain("Hello 🧑‍💻")), .plain(" Cafe\u{301}")])),
            .details(title: .plain("详情"), blocks: [.paragraph(.italic(.plain("未发送的内容")))], expanded: false)
        ], media: [:], isComplete: true, rtl: false, url: "", views: nil)
        let data = try AdaptedPostboxEncoder().encode(ChatRichTextDraftEntry(page: page))
        let restored = try AdaptedPostboxDecoder().decode(ChatRichTextDraftEntry.self, from: data)
        XCTAssertEqual(restored.page, page)
    }

    func testDraftDecoderRejectsMissingPage() throws {
        struct EmptyDraft: Encodable {}
        let data = try AdaptedPostboxEncoder().encode(EmptyDraft())
        XCTAssertThrowsError(try AdaptedPostboxDecoder().decode(ChatRichTextDraftEntry.self, from: data))
    }
}
