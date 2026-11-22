import Foundation

public enum RGAdFilter {
    public static func project(
        _ input: RGAdInput, rules: [RGAdRule] = [], predictions: [RGAdPrediction] = [], threshold: Double = 0.98,
        suggestedRanges: [RGAdRange] = [], confirmedRanges: [RGAdRange] = [], confirmedButtonIds: Set<String> = [],
        preservedButtonIds: Set<String> = [], inferButtons: Bool = true, entireMessageIsAd: Bool = false, disclosedRanges: [RGAdRange] = [],
        promotionalQuoteRanges: [RGAdRange] = []
    ) throws -> RGAdProjection {
        guard input.text.utf16.count <= 65_536, input.entities.count <= 2048, rules.count <= 128,
            predictions.count <= 1024, suggestedRanges.count <= 1024, confirmedRanges.count <= 1024, disclosedRanges.count <= 128,
            promotionalQuoteRanges.count <= 128, confirmedButtonIds.count <= 128, preservedButtonIds.count <= 128,
            input.buttons.count <= 128
        else { throw RGAdFilterError.invalidInput }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        let boundaries = rgAdBoundaries(input.text)
        let allButtons = input.buttons.flatMap { $0 }
        guard allButtons.count <= 128, allButtons.allSatisfy({ $0.title.utf16.count <= 1024 }), threshold.isFinite,
            (0...1).contains(threshold),
            input.entities.allSatisfy({ rgAdValid($0.range, boundaries: boundaries) }),
            Set(allButtons.map(\.id)).count == allButtons.count
        else { throw RGAdFilterError.invalidInput }
        let source = input.text as NSString
        let paragraphs = paragraphRanges(input.text)
        let navigation = navigationRows(input).values.flatMap { $0 }
        let modelSegments = semanticRanges(input.text, entities: input.entities) + navigation
        let approvedQuotes = Set(
            promotionalQuoteRanges.filter { range in
                predictions.contains {
                    $0.range == range && $0.confidence.isFinite && $0.confidence >= max(0.99, threshold) && $0.confidence <= 1
                }
            })
        var ranges: [RGAdRange] = suggestedRanges + confirmedRanges
        var removedButtons = confirmedButtonIds
        let activeRules = rules.filter { !$0.pattern.isEmpty && ($0.peerId == nil || $0.peerId == input.peerId) }
        for rule in activeRules {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw RGAdFilterError.budgetExceeded }
            let matches: [RGAdRange]
            if rule.kind == .target {
                matches = input.entities.compactMap { entity in
                    guard let target = entityTarget(entity, text: source), target == normalizedTarget(rule.pattern) else { return nil }
                    return entity.range
                }
            } else {
                matches = matchRanges(rule, text: input.text)
            }
            for match in matches {
                if rule.scope == .paragraph {
                    ranges += paragraphs.filter { $0.intersects(match) }
                } else {
                    ranges.append(match)
                }
            }
            for button in allButtons {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw RGAdFilterError.budgetExceeded }
                let matched: Bool
                if rule.kind == .target {
                    matched = normalizedTarget(button.target) != nil && normalizedTarget(button.target) == normalizedTarget(rule.pattern)
                } else {
                    matched = !matchRanges(rule, text: button.title).isEmpty
                }
                if matched { removedButtons.insert(button.id) }
            }
        }
        ranges += predictions.filter { prediction in
            guard prediction.confidence.isFinite, prediction.confidence >= threshold, prediction.confidence <= 1,
                rgAdValid(prediction.range, boundaries: boundaries),
                modelSegments.contains(where: { $0.lower == prediction.range.lower }),
                modelSegments.contains(where: { $0.upper == prediction.range.upper })
            else { return false }
            return navigation.contains(prediction.range)
                || source.substring(with: prediction.range.nsRange).trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
        }.map(\.range)
        ranges = ranges.filter { range in
            guard rgAdValid(range, boundaries: boundaries) else { return false }
            return !input.entities.contains { entity in
                guard entity.range.intersects(range) else { return false }
                switch entity.kind {
                case .code:
                    let wholeCard =
                        entireMessageIsAd && range == RGAdRange(0, source.length)
                        && (isInlineCodeLabel(entity, source: source)
                            || (disclosedRanges.contains(range) && RGAdDisclosure.isTextLabel(entity, source: source))
                            || (!disclosedRanges.isEmpty && RGAdDisclosure.isProseBlock(entity, source: source)))
                    return !wholeCard && !confirmedRanges.contains(where: { $0.contains(range) })
                case .quote:
                    let wholeCard = entireMessageIsAd && range == RGAdRange(0, source.length)
                    let disclosedSection = disclosedRanges.contains(range) && range.contains(entity.range)
                    let commercialSection = approvedQuotes.contains(range) && range.contains(entity.range)
                    return !wholeCard && !disclosedSection && !commercialSection && !confirmedRanges.contains(where: { $0.contains(range) })
                case .link, .mention, .customEmoji: return !range.contains(entity.range)
                case .format: return false
                }
            }
        }
        ranges = merge(ranges)
        for (index, paragraph) in paragraphs.enumerated() {
            let line = source.substring(with: paragraph.nsRange)
            let suffix = String(
                line.trimmingCharacters(in: .whitespacesAndNewlines).reversed().prefix { "-=─━═_—".contains($0) }.reversed())
            guard suffix.count >= 3 else { continue }
            let suffixRange = (line as NSString).range(of: suffix, options: .backwards)
            let lower = paragraph.lower + suffixRange.location
            var next = index + 1
            while next < paragraphs.count
                && source.substring(with: paragraphs[next].nsRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            { next += 1 }
            let separatorBlock = RGAdRange(lower, next < paragraphs.count ? paragraphs[next].lower : paragraph.upper)
            if next < paragraphs.count && ranges.contains(where: { $0.contains(paragraphs[next]) }) {
                let protected = input.entities.contains { entity in
                    guard entity.kind != .format, entity.range.intersects(separatorBlock) else { return false }
                    if separatorBlock.contains(entity.range), let target = entityTarget(entity, text: source),
                        input.entities.contains(where: { other in
                            entityTarget(other, text: source) == target && ranges.contains(where: { $0.contains(other.range) })
                        })
                    {
                        return false
                    }
                    return true
                }
                if !protected { ranges.append(separatorBlock) }
            }
        }
        ranges = merge(ranges)
        let blocks = ranges
        for (previous, next) in zip(blocks, blocks.dropFirst()) where previous.upper < next.lower {
            let gap = RGAdRange(previous.upper, next.lower)
            if !source.substring(with: gap.nsRange).unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }),
                !input.entities.contains(where: { ![.format, .customEmoji].contains($0.kind) && $0.range.intersects(gap) })
            {
                ranges.append(gap)
            }
        }
        ranges = merge(ranges)
        for paragraph in inferButtons ? paragraphs : [] {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw RGAdFilterError.budgetExceeded }
            let text = source.substring(with: paragraph.nsRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let target = normalizedTarget(text),
                !input.entities.contains(where: { [.code, .quote].contains($0.kind) && $0.range.intersects(paragraph) }),
                let previous = ranges.last(where: { $0.upper <= paragraph.lower }),
                source.substring(with: NSRange(location: previous.upper, length: paragraph.lower - previous.upper)).trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty,
                input.entities.contains(where: { previous.contains($0.range) && entityTarget($0, text: source) == target }),
                !input.entities.contains(where: {
                    [.link, .mention, .customEmoji].contains($0.kind) && $0.range.intersects(paragraph) && !paragraph.contains($0.range)
                })
            else { continue }
            ranges.append(paragraph)
            ranges = merge(ranges)
        }
        let orphanLinks = inferButtons ? orphanLinkRanges(input, removed: ranges, preservedButtonIds: preservedButtonIds) : nil
        if let orphanLinks { ranges = merge(ranges + orphanLinks) }
        let remaining = complement(ranges, length: source.length)
        var text = ""
        var mappedEntities: [RGAdEntity] = []
        var offset = 0
        for kept in remaining {
            text += source.substring(with: kept.nsRange)
            for entity in input.entities where entity.range.intersects(kept) {
                let clipped = RGAdRange(max(entity.range.lower, kept.lower), min(entity.range.upper, kept.upper))
                mappedEntities.append(
                    RGAdEntity(
                        range: RGAdRange(offset + clipped.lower - kept.lower, offset + clipped.upper - kept.lower), kind: entity.kind,
                        value: entity.value))
            }
            offset += kept.upper - kept.lower
        }
        var removedTargets = Set<String>()
        var keptTargets = Set<String>()
        for entity in input.entities {
            guard let target = entityTarget(entity, text: source) else { continue }
            if ranges.contains(where: { $0.contains(entity.range) }) { removedTargets.insert(target) } else { keptTargets.insert(target) }
        }
        removedTargets.subtract(keptTargets)
        for button in allButtons {
            if inferButtons, let target = normalizedTarget(button.target), removedTargets.contains(target) {
                removedButtons.insert(button.id)
            }
        }
        removedButtons.subtract(preservedButtonIds)
        let buttons = input.buttons.map { $0.filter { !removedButtons.contains($0.id) } }.filter { !$0.isEmpty }
        let hidePreview = normalizedTarget(input.previewTarget).map { removedTargets.contains($0) } ?? false
        let changed = !ranges.isEmpty || !removedButtons.isEmpty || hidePreview
        let hide =
            (changed || entireMessageIsAd) && (!input.hasMedia || entireMessageIsAd)
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && buttons.isEmpty
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw RGAdFilterError.budgetExceeded }
        return RGAdProjection(
            disposition: hide ? .hide : (changed ? .trim : .keep), text: text, entities: mappedEntities, buttons: buttons,
            removedRanges: ranges, removedButtonIds: allButtons.map(\.id).filter { removedButtons.contains($0) },
            hideLinkPreview: hidePreview)
    }

    private static func orphanLinkRanges(_ input: RGAdInput, removed: [RGAdRange], preservedButtonIds: Set<String>) -> [RGAdRange]? {
        guard !removed.isEmpty else { return nil }
        let lines = paragraphRanges(input.text)
        let source = input.text as NSString
        guard lines.count <= 128 else { return nil }
        let protectedTargets = Set(
            input.buttons.flatMap { $0 }.compactMap { button in
                preservedButtonIds.contains(button.id) ? normalizedTarget(button.target) : nil
            })
        func wordCount(_ range: RGAdRange) -> Int {
            source.substring(with: range.nsRange).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        }
        func uncovered(_ range: RGAdRange, by cuts: [RGAdRange]) -> [RGAdRange] {
            complement(
                merge(
                    cuts.compactMap { cut in
                        guard cut.intersects(range) else { return nil }
                        return RGAdRange(max(range.lower, cut.lower) - range.lower, min(range.upper, cut.upper) - range.lower)
                    }), length: range.upper - range.lower
            ).map { RGAdRange($0.lower + range.lower, $0.upper + range.lower) }
        }
        var candidates = Set<Int>()
        var anchors: [Int: Bool] = [:]
        var totalWords = 0
        var removedWords = 0
        for (index, line) in lines.enumerated() {
            let links = input.entities.filter { [.link, .mention].contains($0.kind) && line.contains($0.range) }
            let protected = input.entities.contains { entity in
                entity.range.intersects(line)
                    && ([.code, .quote].contains(entity.kind)
                        || ([.link, .mention, .customEmoji].contains(entity.kind) && !line.contains(entity.range)))
            }
            let linkOnly =
                !links.isEmpty && !protected
                && links.allSatisfy { entity in
                    entityTarget(entity, text: source) != nil
                        && (normalizedTarget(source.substring(with: entity.range.nsRange)) != nil
                            || wordCount(entity.range) <= 24)
                } && uncovered(line, by: links.map(\.range)).allSatisfy { wordCount($0) == 0 }
            if linkOnly {
                if !links.contains(where: { entityTarget($0, text: source).map(protectedTargets.contains) ?? false }) {
                    candidates.insert(index)
                } else {
                    anchors[index] = false
                }
                continue
            }
            let body = uncovered(line, by: links.filter { normalizedTarget(source.substring(with: $0.range.nsRange)) != nil }.map(\.range))
            let total = body.reduce(0) { $0 + wordCount($1) }
            let kept = body.flatMap { uncovered($0, by: removed) }.reduce(0) { $0 + wordCount($1) }
            totalWords += total
            removedWords += total - kept
            if total > 0 || protected { anchors[index] = total > 0 && kept == 0 && !protected }
        }
        guard removedWords >= 12, totalWords > 0, removedWords * 5 >= totalWords * 3 else { return nil }
        let positions = anchors.keys.sorted()
        return candidates.sorted().compactMap { index in
            let neighbors = [positions.last(where: { $0 < index }), positions.first(where: { $0 > index })].compactMap { $0 }
            guard !neighbors.isEmpty, neighbors.allSatisfy({ anchors[$0] == true }) else { return nil }
            return lines[index]
        }
    }

    private static func matchRanges(_ rule: RGAdRule, text: String) -> [RGAdRange] {
        let source = text as NSString
        guard source.length <= 65_536, rule.pattern.utf16.count <= 4096 else { return [] }
        if rule.kind == .regex {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) else { return [] }
            let deadline = ProcessInfo.processInfo.systemUptime + 0.005
            var result: [RGAdRange] = []
            var timedOut = false
            regex.enumerateMatches(in: text, options: .reportProgress, range: NSRange(location: 0, length: source.length)) {
                match, _, stop in
                if ProcessInfo.processInfo.systemUptime >= deadline || result.count >= 1024 {
                    timedOut = true
                    stop.pointee = true
                } else if let range = match?.range, range.length > 0 {
                    result.append(RGAdRange(range.location, NSMaxRange(range)))
                }
            }
            return timedOut ? [] : result
        }
        var result: [RGAdRange] = []
        var start = 0
        while start < source.length && result.count < 1024 {
            let range = source.range(
                of: rule.pattern, options: .caseInsensitive, range: NSRange(location: start, length: source.length - start))
            if range.location == NSNotFound || range.length == 0 { break }
            result.append(RGAdRange(range.location, NSMaxRange(range)))
            start = NSMaxRange(range)
        }
        return result
    }

    static func paragraphRanges(_ text: String) -> [RGAdRange] {
        var result: [RGAdRange] = []
        var lower = 0
        var offset = 0
        for character in text {
            offset += String(character).utf16.count
            if character.isNewline {
                result.append(RGAdRange(lower, offset))
                lower = offset
            }
        }
        if lower < offset { result.append(RGAdRange(lower, offset)) }
        return result
    }

    static func contextRanges(_ text: String) -> [RGAdRange] {
        let source = text as NSString
        var result: [RGAdRange] = []
        var start: Int?
        for line in paragraphRanges(text) {
            if source.substring(with: line.nsRange).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let lower = start {
                    result.append(RGAdRange(lower, line.lower))
                    start = nil
                }
            } else if start == nil {
                start = line.lower
            }
        }
        if let start { result.append(RGAdRange(start, source.length)) }
        return result
    }

    static func semanticRanges(_ text: String, entities: [RGAdEntity] = []) -> [RGAdRange] {
        var result: [RGAdRange] = []
        var lower = 0
        var offset = 0
        let atomic = entities.filter { [.link, .mention, .customEmoji].contains($0.kind) }.map(\.range)
        for character in text {
            offset += String(character).utf16.count
            let punctuation = "。！？；!?;".contains(character) && !atomic.contains { $0.lower < offset && offset <= $0.upper }
            if character.isNewline || punctuation {
                result.append(RGAdRange(lower, offset))
                lower = offset
            }
        }
        if lower < offset { result.append(RGAdRange(lower, offset)) }
        return result
    }

    static func navigationRows(_ input: RGAdInput) -> [RGAdRange: [RGAdRange]] {
        guard input.entities.filter({ $0.kind == .link }).count >= 2 else { return [:] }
        let source = input.text as NSString
        let boundaries = rgAdBoundaries(input.text)
        let lines = paragraphRanges(input.text)
        guard lines.count <= 128 else { return [:] }
        var result: [RGAdRange: [RGAdRange]] = [:]
        for line in lines {
            let fragments = input.entities.filter {
                $0.kind == .link && line.contains($0.range) && rgAdValid($0.range, boundaries: boundaries)
            }.sorted { $0.range.lower < $1.range.lower }
            var links: [RGAdEntity] = []
            for fragment in fragments {
                if let previous = links.last, previous.range.upper == fragment.range.lower,
                    let target = normalizedTarget(previous.value), target == normalizedTarget(fragment.value)
                {
                    links[links.count - 1] = RGAdEntity(
                        range: RGAdRange(previous.range.lower, fragment.range.upper), kind: .link, value: previous.value)
                } else {
                    links.append(fragment)
                }
            }
            guard (2...8).contains(links.count),
                !input.entities.contains(where: { [.quote, .code].contains($0.kind) && $0.range.intersects(line) })
            else { continue }
            var cursor = line.lower
            var units: [RGAdRange] = []
            var valid = true
            for link in links {
                guard link.range.lower >= cursor else {
                    valid = false
                    break
                }
                let label = source.substring(with: link.range.nsRange)
                let gap = source.substring(with: NSRange(location: cursor, length: link.range.lower - cursor))
                guard (1...12).contains(label.count), normalizedTarget(label) == nil,
                    !gap.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) })
                else {
                    valid = false
                    break
                }
                units.append(RGAdRange(cursor, link.range.upper))
                cursor = link.range.upper
            }
            guard valid, let last = units.last,
                !source.substring(with: NSRange(location: cursor, length: line.upper - cursor)).unicodeScalars.contains(where: {
                    CharacterSet.alphanumerics.contains($0)
                })
            else { continue }
            var upper = line.upper
            while upper > cursor, let scalar = UnicodeScalar(source.character(at: upper - 1)), CharacterSet.newlines.contains(scalar) {
                upper -= 1
            }
            units[units.count - 1] = RGAdRange(last.lower, upper)
            guard
                !input.entities.contains(where: { entity in
                    [.link, .mention, .customEmoji].contains(entity.kind)
                        && units.contains(where: { $0.intersects(entity.range) && !$0.contains(entity.range) })
                })
            else { continue }
            result[line] = units
        }
        return result
    }

    static func isSeparator(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count >= 3 && value.unicodeScalars.allSatisfy { "-=─━═_—".unicodeScalars.contains($0) }
    }

    static func isInlineCodeLabel(_ entity: RGAdEntity, source: NSString) -> Bool {
        guard entity.kind == .code, entity.range.lower >= 0, entity.range.upper <= source.length,
            (1...32).contains(entity.range.upper - entity.range.lower)
        else { return false }
        return source.substring(with: entity.range.nsRange).trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "_-".unicodeScalars.contains($0))
        }
    }

    private static func entityTarget(_ entity: RGAdEntity, text: NSString) -> String? {
        guard entity.kind == .link || entity.kind == .mention else { return nil }
        return normalizedTarget(entity.value ?? text.substring(with: entity.range.nsRange))
    }

    public static func normalizedTarget(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        func username(_ value: String) -> String? {
            guard (1...32).contains(value.count),
                value.unicodeScalars.allSatisfy({
                    (65...90).contains($0.value) || (97...122).contains($0.value) || (48...57).contains($0.value) || $0 == "_"
                })
            else { return nil }
            return "telegram-user:" + value.lowercased()
        }
        if value.hasPrefix("@") { return username(String(value.dropFirst())) }
        guard var url = URLComponents(string: value), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
            let host = url.host?.lowercased(), url.user == nil, url.password == nil
        else { return nil }
        if ["t.me", "telegram.me"].contains(host), url.port == nil, url.query == nil, url.fragment == nil {
            let components = url.path.split(separator: "/")
            if components.count == 1, let identity = username(String(components[0])) { return identity }
        }
        url.scheme = scheme
        url.host = host
        if (scheme == "https" && url.port == 443) || (scheme == "http" && url.port == 80) { url.port = nil }
        if url.path.isEmpty { url.path = "/" }
        return url.string
    }

    private static func merge(_ input: [RGAdRange]) -> [RGAdRange] {
        var result: [RGAdRange] = []
        for range in input.sorted(by: { $0.lower == $1.lower ? $0.upper < $1.upper : $0.lower < $1.lower }) {
            if let last = result.last, last.upper >= range.lower {
                result[result.count - 1] = RGAdRange(last.lower, max(last.upper, range.upper))
            } else {
                result.append(range)
            }
        }
        return result
    }

    private static func complement(_ removed: [RGAdRange], length: Int) -> [RGAdRange] {
        var result: [RGAdRange] = []
        var offset = 0
        for range in removed {
            if offset < range.lower { result.append(RGAdRange(offset, range.lower)) }
            offset = range.upper
        }
        if offset < length { result.append(RGAdRange(offset, length)) }
        return result
    }
}
