import AppKit
import Foundation
import InputView
import Postbox
import TelegramCore
import RegramCore

private func verify(_ value: @autoclosure () -> Bool, _ label: String) {
    if !value() {
        FileHandle.standardError.write(Data((label + "\n").utf8))
        exit(1)
    }
}

private func style(_ value: String, _ range: Range<Int>) -> ChatTextInputAttribute? {
    switch value {
    case "bold": return .bold(range)
    case "italic": return .italic(range)
    case "underline": return .underline(range)
    case "strikethrough": return .strikethrough(range)
    case "spoiler": return .spoiler(range)
    default: return nil
    }
}

@main
struct OutgoingCombinationChecks {
    static func main() throws {
        UITestBootstrap.install()
        let peer = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(2))
        let sameNumberUser = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2))
        let input = ChatTextInputState(inputText: "中文hello世界", selectionRange: 2..<2, attributes: [])
        let formats = ["none", "bold", "italic", "underline", "strikethrough", "spoiler"]
        let overrides: [String?] = [nil, "none", "bold", "italic", "underline", "strikethrough", "spoiler"]
        let spacingOverrides: [Bool?] = [nil, false, true]
        var plainCases = 0
        for format in formats {
            for spacing in [false, true] {
                for override in overrides {
                    for spacingOverride in spacingOverrides {
                        for mask in 0..<16 {
                            var settings = RegramAccountSettings()
                            settings["defaultOutgoingFormatting"] = .string(format)
                            settings["panguSpacing"] = .bool(spacing)
                            settings["allowSavingProtectedContent"] = .bool(mask & 1 != 0)
                            settings["quickTranslateButton"] = .bool(mask & 2 != 0)
                            settings["features.enablePanguOnReceiving"] = .bool(mask & 4 != 0)
                            settings["features.enablePanguOnEditing"] = .bool(mask & 8 != 0)
                            settings["translationBackend"] = .string(mask & 1 != 0 ? "llm" : "default")
                            settings["transcriptionBackend"] = .string(mask & 2 != 0 ? "apple" : "default")
                            settings["features.autoInlineBotEnabled"] = .bool(mask & 4 != 0)
                            settings["disableLinkPreview"] = .bool(mask & 8 != 0)
                            let values = [RGChatPreferences.key(accountId: 101, peerId: peer.toInt64()): RGChatPreferences(formatting: override, panguSpacing: spacingOverride)]
                            settings["chatPreferences"] = .string(String(data: try JSONEncoder().encode(values), encoding: .utf8)!)
                            for (account, destination, expectedFormat, expectedSpacing) in [(Int64(101), peer, override ?? format, spacingOverride ?? spacing), (Int64(101), sameNumberUser, format, spacing), (Int64(202), peer, format, spacing)] {
                                let result = combinationOutgoingInput(input, settings: settings, accountId: account, peerId: destination)
                                let text = expectedSpacing ? "中文 hello 世界" : "中文hello世界"
                                verify(result.inputText == text, "Spacing crossed a chat/account boundary or unrelated feature")
                                let expectedAttributes = style(expectedFormat, 0..<text.utf16.count).map { [$0] } ?? []
                                verify(result.attributes == expectedAttributes, "Formatting crossed a chat/account boundary or unrelated feature")
                                let selection = expectedSpacing ? text.utf16.count..<text.utf16.count : input.selectionRange
                                verify(result.selectionRange == selection, "Transformation changed selection unexpectedly")
                                let restored = try JSONDecoder().decode(ChatTextInputState.self, from: JSONEncoder().encode(result))
                                verify(restored == result, "Combined formatting failed draft serialization")
                                plainCases += 1
                            }
                        }
                    }
                }
            }
        }
        let text = "前中文A @测试 后中文B https://example.test 中文C 代码D 🙂\n预格式F\n引用E\n2026年10月30日\n尾中文G"
        let source = text as NSString
        func range(_ value: String) -> Range<Int> {
            let found = source.range(of: value)
            return found.location..<(found.location + found.length)
        }
        let protectedInput = ChatTextInputState(inputText: text, selectionRange: text.utf16.count..<text.utf16.count, attributes: [.uid(range("@测试"), 8_559_682_245), .url(range("https://example.test"), "https://example.test"), .code(range("代码D")), .pre(range("预格式F"), "swift"), .animated(range("🙂"), "fixture-emoji", 9_000_000_001, nil, nil), .quote(range("引用E"), false), .date(range("2026年10月30日"), 1_800_000_000)])
        var protectedCases = 0
        for format in formats {
            for spacing in [false, true] {
                var settings = RegramAccountSettings()
                settings["defaultOutgoingFormatting"] = .string(format)
                settings["panguSpacing"] = .bool(spacing)
                let result = combinationOutgoingInput(protectedInput, settings: settings, accountId: 101, peerId: peer)
                let restored = try JSONDecoder().decode(ChatTextInputState.self, from: JSONEncoder().encode(result))
                verify(restored == result, "Combined protected entities failed draft serialization")
                let entities = result.messageTextEntities()
                var protectedRanges: [Range<Int>] = []
                for (kind, original) in [(0, "@测试"), (1, "https://example.test"), (2, "代码D"), (3, "预格式F"), (4, "🙂"), (5, "引用E"), (6, "2026年10月30日")] {
                    let entity = entities.first { entity in
                        switch entity.type {
                        case let .TextMention(id): return kind == 0 && id.id._internalGetInt64Value() == 8_559_682_245
                        case let .TextUrl(url): return kind == 1 && url == original
                        case .Code: return kind == 2
                        case let .Pre(language): return kind == 3 && language == "swift"
                        case let .CustomEmoji(_, fileId): return kind == 4 && fileId == 9_000_000_001
                        case .BlockQuote: return kind == 5
                        case let .FormattedDate(_, date): return kind == 6 && date == 1_800_000_000
                        default: return false
                        }
                    }
                    verify(entity != nil, "Combined Pangu/formatting lost protected kind=\(kind), format=\(format), spacing=\(spacing); entities=\(entities)")
                    let found = entity!.range
                    verify((result.inputText as NSString).substring(with: NSRange(location: found.lowerBound, length: found.count)) == original, "Combined transformation edited protected content")
                    protectedRanges.append(found)
                }
                for attribute in result.attributes {
                    let styled: Range<Int>?
                    switch attribute {
                    case let .bold(range), let .italic(range), let .underline(range), let .strikethrough(range), let .spoiler(range): styled = range
                    default: styled = nil
                    }
                    if let styled { verify(protectedRanges.allSatisfy { !$0.overlaps(styled) }, "Automatic style crossed a protected entity") }
                }
                protectedCases += 1
            }
        }
        var spacedSettings = RegramAccountSettings()
        spacedSettings["panguSpacing"] = .bool(true)
        let spacedInput = combinationOutgoingInput(protectedInput, settings: spacedSettings, accountId: 101, peerId: peer)
        for mask in 0..<16 {
            var settings = RegramAccountSettings()
            settings["panguSpacing"] = .bool(mask & 1 != 0)
            settings["features.enablePanguOnEditing"] = .bool(mask & 2 != 0)
            settings["features.enablePanguOnReceiving"] = .bool(mask & 4 != 0)
            settings["defaultOutgoingFormatting"] = .string(mask & 8 != 0 ? "spoiler" : "bold")
            let result = combinationEditingInput(protectedInput, settings: settings)
            verify(result == (mask & 2 != 0 ? spacedInput : protectedInput), "Editing inherited another feature's spacing or default formatting")
        }
        let report: [String: Any] = ["plainInputCases": plainCases, "protectedInputCases": protectedCases, "editingInputCases": 16, "protectedEntityKinds": 7, "accountAndPeerNamespaceIsolation": true, "realInputModels": true, "chatMessagesSent": 0, "networkRequests": 0, "realAccountPreferencesChanged": false]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "report.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
