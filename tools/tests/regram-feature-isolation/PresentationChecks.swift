import Foundation
import RegramCore

enum TranslationTone: String { case neutral, formal }
protocol MessageAttribute {}
struct RegramTranslationMessageAttribute: MessageAttribute {
    let configuration: String
    var quickToLang: String?
}
struct TranslationMessageAttribute: MessageAttribute { let language: String }
struct Message {
    let attributes: [MessageAttribute]
    func translationAttribute(toLang language: String) -> TranslationMessageAttribute? {
        attributes.compactMap { $0 as? TranslationMessageAttribute }.first { $0.language == language }
    }
}

var identityEncodings = 0
func recordTranslationIdentity(_ settings: RegramAccountSettings) -> String {
    identityEncodings += 1
    return settings.translationIdentity
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

@main
struct PresentationChecks {
    static func main() throws {
        var settings = RegramAccountSettings()
        settings["translationBackend"] = .string("llm")
        settings["translationLLMPrompt"] = .string(String(repeating: "Translate the input. ", count: 160))
        let identity = settings.translationIdentity
        let selected = Message(attributes: [RegramTranslationMessageAttribute(configuration: regramTranslationCacheIdentity(identity, tone: .formal)), TranslationMessageAttribute(language: "ja")])
        let quick = Message(attributes: [RegramTranslationMessageAttribute(configuration: identity, quickToLang: "ja"), TranslationMessageAttribute(language: "ja")])
        let hidden = Message(attributes: [RegramTranslationMessageAttribute(configuration: identity, quickToLang: ""), TranslationMessageAttribute(language: "ja")])
        let stale = Message(attributes: [RegramTranslationMessageAttribute(configuration: "old", quickToLang: "ja"), TranslationMessageAttribute(language: "ja")])
        let missing = Message(attributes: [RegramTranslationMessageAttribute(configuration: identity, quickToLang: "ja")])
        let empty = Message(attributes: [])
        let messages = [selected, quick, hidden, stale, missing, empty]
        let presentation = RegramTranslationPresentation(settings: settings, tone: .formal)
        identityEncodings = 0
        for _ in 0..<500 {
            for (index, message) in messages.enumerated() {
                check(presentation.matches(message) == (index == 0), "Selected-provider translation mismatch")
                check(presentation.quickLanguage(message) == (index == 1 ? "ja" : nil), "Quick translation mismatch")
                check(presentation.hidesQuickTranslation(message) == (index == 2), "Hidden translation mismatch")
            }
        }
        check(identityEncodings == 1, "A batch must encode its configuration only once")
        identityEncodings = 0
        let untranslated = RegramTranslationPresentation(settings: settings)
        for _ in 0..<500 {
            check(!untranslated.matches(empty), "Untranslated message matched")
            check(untranslated.quickLanguage(empty) == nil, "Untranslated message has quick translation")
            check(!untranslated.hidesQuickTranslation(empty), "Untranslated message was hidden")
        }
        check(identityEncodings == 0, "Untranslated messages must not encode translation configuration")
        var speech = settings
        speech["sttModel"] = .string("speech")
        speech["transcriptionConfigurationRevision"] = .integer(1)
        check(RegramTranslationPresentation(settings: speech, tone: .formal).matches(selected), "Speech edits invalidated translation")
        speech["translationConfigurationRevision"] = .integer(1)
        check(!RegramTranslationPresentation(settings: speech, tone: .formal).matches(selected), "Translation edits were ignored")

        var choices = RegramAccountSettings()
        let peers: [Int64] = [17, (1 << 32) | 17, (2 << 32) | 17]
        choices["outgoingLanguageTranslation"] = .dictionary(Dictionary(uniqueKeysWithValues: zip(peers, ["en", "ja", "off"]).map { (RegramOutgoingTranslationPolicy.key(accountId: 42, peerId: $0.0), $0.1) }))
        check(RegramOutgoingTranslationPolicy.language(settings: choices, accountId: 42, peerId: peers[0]) == "en", "User language changed")
        check(RegramOutgoingTranslationPolicy.language(settings: choices, accountId: 42, peerId: peers[1]) == "ja", "Group language collided with user")
        check(RegramOutgoingTranslationPolicy.language(settings: choices, accountId: 42, peerId: peers[2]) == nil, "Channel off ignored")
        check(RegramOutgoingTranslationPolicy.language(settings: choices, accountId: 43, peerId: peers[0]) == nil, "Account language isolation failed")
        choices["outgoingLanguageTranslation"] = .dictionary(["42:17": "de"])
        check(RegramOutgoingTranslationPolicy.language(settings: choices, accountId: 42, peerId: 17) == nil, "Ambiguous legacy key was used")

        let batch = (0..<240).map { messages[$0 % messages.count] }
        var checksum = 0
        func process(reuse: Bool) {
            let shared = RegramTranslationPresentation(settings: settings, tone: .formal)
            for message in batch {
                let current = reuse ? shared : RegramTranslationPresentation(settings: settings, tone: .formal)
                if current.matches(message) { checksum &+= 1 }
                if current.quickLanguage(message) != nil { checksum &+= 2 }
                if current.hidesQuickTranslation(message) { checksum &+= 4 }
            }
        }
        func measure(reuse: Bool) -> [Double] {
            process(reuse: reuse)
            return (0..<25).map { _ in
                let start = ProcessInfo.processInfo.systemUptime
                process(reuse: reuse)
                return (ProcessInfo.processInfo.systemUptime - start) * 1000
            }.sorted()
        }
        let perMessage = measure(reuse: false)
        let perBatch = measure(reuse: true)
        let report: [String: Any] = [
            "fixtureMessagesPerBatch": batch.count,
            "iterations": 25,
            "perMessageMedianMs": perMessage[12],
            "perMessageP95Ms": perMessage[23],
            "perBatchMedianMs": perBatch[12],
            "perBatchP95Ms": perBatch[23],
            "checksum": checksum,
            "liveFPSMeasured": false,
            "boundary": "Production translation presentation code and RegramCore configuration encoding; fixture message/attribute access only"
        ]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }
}
