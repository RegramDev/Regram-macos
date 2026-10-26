import XCTest
@testable import RegramCore

final class RegramNicknameMentionPolicyTests: XCTestCase {
    private func range(_ token: String, in text: String) -> Range<Int> {
        let value = (text as NSString).range(of: token)
        return value.location..<(value.location + value.length)
    }

    func testUsernameCandidatesUseUtf16AndWaitForCaretToLeaveToken() {
        let text = "😊 @SomeUser "
        let mention = range("@SomeUser", in: text)
        let end = text.utf16.count
        let candidates = RegramNicknameMentionPolicy.candidates(text: text, mentionRanges: [mention, mention], excludedRanges: [], selection: end..<end)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.username, "someuser")
        XCTAssertEqual(candidates.first?.range.lowerBound, 3)
        XCTAssertTrue(RegramNicknameMentionPolicy.candidates(text: text, mentionRanges: [mention], excludedRanges: [], selection: 4..<4).isEmpty)
        XCTAssertTrue(RegramNicknameMentionPolicy.candidates(text: text, mentionRanges: [mention], excludedRanges: [], selection: mention).isEmpty)
    }

    func testSemanticAndCodeRangesProtectMentionsWhileOtherTokensRemainEligible() {
        let text = "@first @second @third"
        let first = range("@first", in: text)
        let second = range("@second", in: text)
        let third = range("@third", in: text)
        let end = text.utf16.count
        let candidates = RegramNicknameMentionPolicy.candidates(text: text, mentionRanges: [first, second, third], excludedRanges: [first, second], selection: end..<end)
        XCTAssertEqual(candidates.map(\.username), ["third"])
        XCTAssertTrue(RegramNicknameMentionPolicy.candidates(text: text, mentionRanges: [-1..<3, 0..<100], excludedRanges: [], selection: end..<end).isEmpty)
    }

    func testMultipleFullNamesRemapCaretAndEntityRangesWithoutSplittingEmoji() {
        let text = "🙂 @first and @second"
        let first = range("@first", in: text)
        let second = range("@second", in: text)
        let replacements: [RegramNicknameMentionPolicy.Replacement] = [.init(range: first, text: "李 明"), .init(range: second, text: "😊 Smith ")]
        let updated = "🙂 李 明 and 😊 Smith "
        let end = text.utf16.count
        XCTAssertEqual(RegramNicknameMentionPolicy.remap(end..<end, replacements: replacements), updated.utf16.count..<updated.utf16.count)
        let prefix = "🙂 李 明 and ".utf16.count
        XCTAssertEqual(RegramNicknameMentionPolicy.remap(second, replacements: replacements), prefix..<updated.utf16.count)
        XCTAssertEqual(RegramNicknameMentionPolicy.remap(0..<2, replacements: replacements), 0..<2)
    }
}
