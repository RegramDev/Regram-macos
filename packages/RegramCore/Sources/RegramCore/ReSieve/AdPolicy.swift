import Foundation

public enum RGAdPolicy {
    public static let revision = 8
    private static let warning = try! NSRegularExpression(pattern: "警惕|谨防|诈骗|騙|骗局|报道|報道|曝光|反诈|不要|切勿|案例|举报|舉報|新闻|新聞")
    private static let promotion = try! NSRegularExpression(
        pattern: "0\\s*充值.{0,24}(免费体验|免費體驗).{0,24}(中奖可提现|中獎可提現)|实力飞投.{0,24}超高限红.{0,24}大额无忧|實力飛投.{0,24}超高限紅.{0,24}大額無憂")
    private static let signup = try! NSRegularExpression(pattern: "新人注册送\\s*[0-9]+\\s*[uU]|新人註冊送\\s*[0-9]+\\s*[uU]")
    private static let gambling = try! NSRegularExpression(pattern: "8g\\.com|博彩|盘口|盤口", options: .caseInsensitive)
    private static let brandedPromotion = try! NSRegularExpression(pattern: "(?:白马庄园|白馬莊園).{0,8}(?:大额无忧|大額無憂)")
    private static let gamblingHosts = ["8g.com", "8gtg.vip"]
    private static let cooperation = Set(["广告合作招商", "廣告合作招商"])
    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) != nil
    }

    private static func matchText(_ text: String) -> String {
        String(
            String.UnicodeScalarView(
                text.precomposedStringWithCompatibilityMapping.unicodeScalars.filter {
                    !CharacterSet.whitespacesAndNewlines.contains($0) && ![0x200b, 0x200c, 0x200d, 0x2060, 0xfeff].contains($0.value)
                }))
    }

    private static func gamblingDestination(_ entity: RGAdEntity, source: NSString) -> Bool {
        guard entity.kind == .link,
            let target = RGAdFilter.normalizedTarget(entity.value ?? source.substring(with: entity.range.nsRange)),
            let host = URLComponents(string: target)?.host?.lowercased()
        else { return false }
        return gamblingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private struct ButtonKey: Hashable {
        let title: String
        let target: String
        init?(_ button: RGAdButton) {
            guard let target = RGAdFilter.normalizedTarget(button.target) else { return nil }
            self.title = button.title
            self.target = target
        }
    }

    public struct Knowledge {
        private var exact: [String: [RGAdInput: RGAdSample]] = [:]
        private var reviewedMedia: [String: RGAdSample] = [:]
        private var snippets: [String: [String]] = [:]
        private var buttons: [String: [ButtonKey: RGAdLabel]] = [:]
        public init(samples: [RGAdSample] = []) {
            let valid = samples.filter { $0.reviewedAt != nil && (try? $0.validate()) != nil }.sorted {
                ($0.reviewedAt ?? 0) > ($1.reviewedAt ?? 0)
            }
            for (group, local) in Dictionary(grouping: valid, by: \.sourceGroup) {
                var known: [RGAdInput: RGAdSample] = [:]
                var targets: [ButtonKey: RGAdLabel] = [:]
                var candidates: [String] = []
                var seen = Set<String>()
                for sample in local {
                    if sample.input.hasMedia {
                        reviewedMedia[sample.id] = sample
                    } else if known[sample.input] == nil {
                        known[sample.input] = sample
                    }
                    for button in sample.input.buttons.flatMap({ $0 }) {
                        guard let key = ButtonKey(button), let label = sample.buttonLabels[button.id] else { continue }
                        if targets[key] == nil || label != .ad { targets[key] = label }
                    }
                    for span in sample.spans where span.label == .ad {
                        let snippet = (sample.input.text as NSString).substring(with: span.range.nsRange)
                        if candidates.count < 128, snippet.trimmingCharacters(in: .whitespacesAndNewlines).count >= 12,
                            snippet.utf16.count <= 4096, seen.insert(snippet.lowercased()).inserted
                        {
                            candidates.append(snippet)
                        }
                    }
                }
                exact[group] = known
                buttons[group] = targets
                snippets[group] = candidates.filter { snippet in
                    !local.contains { sample in
                        let text = sample.input.text as NSString
                        var start = 0
                        while start < text.length {
                            let match = text.range(
                                of: snippet, options: .caseInsensitive, range: NSRange(location: start, length: text.length - start))
                            if match.location == NSNotFound { break }
                            let range = RGAdRange(match.location, NSMaxRange(match))
                            if !sample.spans.contains(where: { $0.label == .ad && $0.range.contains(range) }) { return true }
                            start = NSMaxRange(match)
                        }
                        return false
                    }
                }
            }
        }

        private func review(_ input: RGAdInput, sourceGroup: String, sampleId: String?) -> RGAdSample? {
            let sanitized = RGAdInput(
                text: input.text, entities: input.entities, buttons: input.buttons, hasMedia: input.hasMedia,
                previewTarget: input.previewTarget)
            if input.hasMedia {
                guard let sampleId, let sample = reviewedMedia[sampleId], sample.sourceGroup == sourceGroup, sample.input == sanitized
                else { return nil }
                return sample
            }
            return exact[sourceGroup]?[sanitized]
        }

        public func preservesMedia(_ input: RGAdInput, sourceGroup: String, sampleId: String? = nil) -> Bool {
            guard let sample = review(input, sourceGroup: sourceGroup, sampleId: sampleId) else { return false }
            return sample.mediaLabel != .ad || sample.hasUncertainty
        }

        public func requiresSnapshot(for input: RGAdInput) -> Bool { input.hasMedia && !reviewedMedia.isEmpty }

        public func prepare(_ input: RGAdInput, sourceGroup: String = "", sampleId: String? = nil) throws -> (
            projection: RGAdProjection, isFinal: Bool
        ) {
            let projection = try project(input, sourceGroup: sourceGroup, sampleId: sampleId)
            return (
                projection,
                projection.disposition == .hide || review(input, sourceGroup: sourceGroup, sampleId: sampleId) != nil
                    || (input.text.isEmpty && input.buttons.isEmpty)
            )
        }

        public func resolve(
            _ input: RGAdInput, sourceGroup: String = "", sampleId: String? = nil,
            classify: (RGAdInput) -> RGAdSemanticResult
        ) throws -> RGAdProjection {
            let initial = try prepare(input, sourceGroup: sourceGroup, sampleId: sampleId)
            if initial.isFinal { return initial.projection }
            let semantic = classify(input)
            if semantic.predictions.isEmpty, semantic.buttonIds.isEmpty, !semantic.entireMessage, semantic.promotionalQuotes.isEmpty,
                (0...1).contains(semantic.threshold)
            {
                return initial.projection
            }
            return try project(input, sourceGroup: sourceGroup, semantic: semantic, sampleId: sampleId)
        }

        public func project(
            _ input: RGAdInput, sourceGroup: String = "", semantic: RGAdSemanticResult = RGAdSemanticResult(), sampleId: String? = nil
        ) throws -> RGAdProjection {
            guard input.text.utf16.count <= 65_536 else { throw RGAdFilterError.inputTooLong }
            guard input.entities.count <= 2048, input.buttons.count <= 128, input.buttons.flatMap({ $0 }).count <= 128 else {
                throw RGAdFilterError.invalidInput
            }
            if let sample = review(input, sourceGroup: sourceGroup, sampleId: sampleId) {
                let wholeAd =
                    sample.mediaLabel == .ad && sample.buttonLabels.values.allSatisfy { $0 == .ad }
                    && sample.previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sample.hasUncertainty
                return try RGAdFilter.project(
                    input, confirmedRanges: sample.spans.filter { $0.label == .ad }.map(\.range),
                    confirmedButtonIds: Set(sample.buttonLabels.filter { $0.value == .ad }.keys), inferButtons: false,
                    entireMessageIsAd: wholeAd)
            }
            let source = input.text as NSString
            let lines = RGAdFilter.paragraphRanges(input.text)
            let matchingDeadline = ProcessInfo.processInfo.systemUptime + 0.25
            let disclosed = RGAdDisclosure.ranges(input)
            let disclosedWhole = disclosed.contains { $0 == RGAdRange(0, source.length) }
            var ranges: [RGAdRange] = disclosed
            var protected: [RGAdRange] = []
            var precedingPromotion = false
            for line in lines {
                guard ProcessInfo.processInfo.systemUptime < matchingDeadline else { throw RGAdFilterError.budgetExceeded }
                let text = RGAdPolicy.matchText(source.substring(with: line.nsRange))
                if text.isEmpty { continue }
                let adjacentPromotion = precedingPromotion
                precedingPromotion = false
                if RGAdPolicy.matches(RGAdPolicy.warning, text) {
                    protected.append(line)
                    continue
                }
                let entities = input.entities.filter {
                    $0.range.upper > $0.range.lower && $0.range.lower >= 0 && $0.range.upper <= source.length && line.contains($0.range)
                }
                let destination = entities.contains {
                    [.link, .mention].contains($0.kind)
                        && RGAdFilter.normalizedTarget($0.value ?? source.substring(with: $0.range.nsRange)) != nil
                }
                let quoted = input.entities.contains { [.code, .quote].contains($0.kind) && $0.range.intersects(line) }
                let crossesLink = input.entities.contains {
                    [.link, .mention, .customEmoji].contains($0.kind) && $0.range.intersects(line) && !line.contains($0.range)
                }
                let casino =
                    RGAdPolicy.matches(RGAdPolicy.gambling, text)
                    || entities.contains { RGAdPolicy.gamblingDestination($0, source: source) }
                let banner = adjacentPromotion && entities.filter { $0.kind == .customEmoji }.count >= 3 && text.count <= 160
                if destination, !quoted, !crossesLink, text.count >= 12,
                    RGAdPolicy.matches(RGAdPolicy.promotion, text) || (RGAdPolicy.matches(RGAdPolicy.signup, text) && (casino || banner))
                {
                    ranges.append(line)
                    precedingPromotion = true
                }
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 0.1
            for snippet in snippets[sourceGroup] ?? [] {
                var start = 0
                while start < source.length {
                    guard ProcessInfo.processInfo.systemUptime < deadline, ranges.count < 1024 else { throw RGAdFilterError.budgetExceeded }
                    let match = source.range(
                        of: snippet, options: .caseInsensitive, range: NSRange(location: start, length: source.length - start))
                    if match.location == NSNotFound { break }
                    let range = RGAdRange(match.location, NSMaxRange(match))
                    if !protected.contains(where: { $0.intersects(range) }) { ranges.append(range) }
                    start = NSMaxRange(match)
                }
            }
            var removedButtons = semantic.buttonIds
            var preservedButtons = Set<String>()
            if disclosedWhole { removedButtons.formUnion(input.buttons.flatMap { $0 }.map(\.id)) }
            for button in input.buttons.flatMap({ $0 }) {
                guard let key = ButtonKey(button) else { continue }
                if let label = buttons[sourceGroup]?[key] {
                    if label == .ad { removedButtons.insert(button.id) } else { preservedButtons.insert(button.id) }
                } else {
                    let title = RGAdPolicy.matchText(button.title)
                    if !RGAdPolicy.matches(RGAdPolicy.warning, title),
                        RGAdPolicy.cooperation.contains(title) || RGAdPolicy.matches(RGAdPolicy.promotion, title)
                            || RGAdPolicy.matches(RGAdPolicy.brandedPromotion, title)
                            || (RGAdPolicy.matches(RGAdPolicy.signup, title) && RGAdPolicy.matches(RGAdPolicy.gambling, title))
                    {
                        removedButtons.insert(button.id)
                    }
                }
            }
            let result = try RGAdFilter.project(
                input, predictions: semantic.predictions, threshold: semantic.threshold, suggestedRanges: ranges,
                confirmedButtonIds: removedButtons, preservedButtonIds: preservedButtons,
                entireMessageIsAd: semantic.entireMessage || disclosedWhole, disclosedRanges: disclosed,
                promotionalQuoteRanges: semantic.promotionalQuotes)
            if input.hasMedia, result.disposition == .trim, !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, result.buttons.isEmpty
            {
                return RGAdProjection(
                    disposition: .hide, text: result.text, entities: result.entities, buttons: result.buttons,
                    removedRanges: result.removedRanges, removedButtonIds: result.removedButtonIds, hideLinkPreview: result.hideLinkPreview)
            }
            return result
        }
    }

    public static func project(
        _ input: RGAdInput, samples: [RGAdSample] = [], sourceGroup: String = "", semantic: RGAdSemanticResult = RGAdSemanticResult(),
        sampleId: String? = nil
    ) throws -> RGAdProjection {
        try Knowledge(samples: samples).project(input, sourceGroup: sourceGroup, semantic: semantic, sampleId: sampleId)
    }
}
