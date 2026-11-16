import Foundation

enum RGAdDisclosure {
    static let tags = [
        "推广", "推廣", "广告", "廣告", "商业推广", "商業推廣", "付费推广", "付費推廣",
        "商业合作", "商業合作", "付费合作", "付費合作", "业配", "業配", "广宣", "廣宣",
        "ad", "ads", "advert", "adverts", "advertisement", "advertisements", "advertising",
        "sponsored", "sponsoredpost", "sponsored_post", "sponsoredcontent", "sponsored_content",
        "paidpromotion", "paid_promotion", "paidpartnership", "paid_partnership", "promo", "promotion", "promoted",
    ]
    private static let disclosure = try! NSRegularExpression(
        pattern: "(?<![\\p{L}\\p{N}\\p{M}_/#＃])(?:#|＃)(?:" + tags.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            + ")(?![\\p{L}\\p{N}\\p{M}_])",
        options: .caseInsensitive
    )
    private static let hashtag = try! NSRegularExpression(pattern: "[#＃][\\p{L}\\p{N}\\p{M}_]+")
    private static let url = try! NSRegularExpression(pattern: "(?:https?://|tg://|www\\.)[^\\s]+", options: .caseInsensitive)
    private static let tagField = try! NSRegularExpression(
        pattern: "^[\\s\\p{So}\\p{Sk}\\p{M}]*(?:标签|標籤|tags?)\\s*[:：]\\s*$", options: .caseInsensitive)

    private static func onlyTagsAndDecoration(_ text: String) -> Bool {
        let stripped = hashtag.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: text.utf16.count), withTemplate: "")
        return !stripped.contains(where: { "\"'`“”‘’「」『』«»".contains($0) })
            && !stripped.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
    }

    static func isTextLabel(_ entity: RGAdEntity, source: NSString) -> Bool {
        guard entity.kind == .code, entity.range.lower >= 0, entity.range.upper <= source.length,
            (1...128).contains(entity.range.upper - entity.range.lower)
        else { return false }
        let value = source.substring(with: entity.range.nsRange)
        return !value.contains(where: { $0.isNewline || "{}[]=<>\\();".contains($0) })
            && value.unicodeScalars.filter({ (0x3400...0x9fff).contains($0.value) }).count >= 4
    }

    static func isProseBlock(_ entity: RGAdEntity, source: NSString) -> Bool {
        guard entity.kind == .code, entity.range.lower >= 0, entity.range.upper <= source.length,
            (16...1024).contains(entity.range.upper - entity.range.lower)
        else { return false }
        let value = source.substring(with: entity.range.nsRange)
        return value.split(whereSeparator: \.isNewline).count <= 24
            && !value.contains(where: { "{}[]=<>\\();`".contains($0) })
            && value.unicodeScalars.filter({ (0x3400...0x9fff).contains($0.value) }).count >= 16
    }

    static func ranges(_ input: RGAdInput) -> [RGAdRange] {
        let source = input.text as NSString
        guard source.length <= 65_536, input.entities.count <= 2048 else { return [] }
        let matches = disclosure.matches(in: input.text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty, matches.count <= 128 else { return [] }
        let destinations = url.matches(in: input.text, range: NSRange(location: 0, length: source.length)).map {
            RGAdRange($0.range.location, NSMaxRange($0.range))
        }
        let boundaries = rgAdBoundaries(input.text)
        let lines = RGAdFilter.paragraphRanges(input.text)
        let blocks = RGAdFilter.contextRanges(input.text)
        let sentences = RGAdFilter.semanticRanges(input.text, entities: input.entities)
        func text(_ range: RGAdRange) -> String { source.substring(with: range.nsRange) }
        func empty(_ range: RGAdRange) -> Bool { text(range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        func normalTags(_ range: RGAdRange) -> Bool {
            let value = text(range)
            return onlyTagsAndDecoration(value)
                && hashtag.firstMatch(in: value, range: NSRange(location: 0, length: value.utf16.count)) != nil
                && disclosure.firstMatch(in: value, range: NSRange(location: 0, length: value.utf16.count)) == nil
        }
        var result: [RGAdRange] = []
        for match in matches {
            let marker = RGAdRange(match.range.location, NSMaxRange(match.range))
            guard rgAdValid(marker, boundaries: boundaries),
                !destinations.contains(where: { $0.intersects(marker) }),
                !input.entities.contains(where: { $0.kind != .format && $0.range.intersects(marker) }),
                let index = lines.firstIndex(where: { $0.contains(marker) })
            else { continue }
            let line = lines[index]
            let sentence = sentences.first(where: { $0.contains(marker) }) ?? line
            let inlineHead = sentence.lower > line.lower
            let prefix = text(RGAdRange(max(line.lower, sentence.lower), marker.lower))
            let suffix = text(RGAdRange(marker.upper, min(line.upper, sentence.upper)))
            let labelOnly = onlyTagsAndDecoration(text(line))
            let lineText = text(line)
            let lineRange = NSRange(location: 0, length: line.upper - line.lower)
            let firstTag = hashtag.firstMatch(in: lineText, range: lineRange)
            let fieldPrefix = (lineText as NSString).substring(to: firstTag?.range.location ?? 0)
            let hasCategoryField = tagField.firstMatch(in: fieldPrefix, range: NSRange(location: 0, length: fieldPrefix.utf16.count)) != nil
            if hasCategoryField
                && hashtag.numberOfMatches(in: lineText, range: lineRange) != disclosure.numberOfMatches(in: lineText, range: lineRange)
            {
                continue
            }
            let categoryDeclaration = hasCategoryField && onlyTagsAndDecoration(suffix)
            guard labelOnly || onlyTagsAndDecoration(prefix) || onlyTagsAndDecoration(suffix) else { continue }
            if prefix.last.map({ "\"'`“‘「『«".contains($0) }) == true
                || suffix.first.map({ "\"'`”’」』»".contains($0) }) == true
            {
                continue
            }

            var lower = 0
            var upper = source.length
            if index > 0 {
                for previous in lines[..<index].reversed() {
                    let endsEarlierBody =
                        normalTags(previous)
                        && lines.contains { earlier in
                            earlier.upper <= previous.lower && !empty(earlier)
                                && !onlyTagsAndDecoration(text(earlier)) && !RGAdFilter.isSeparator(text(earlier))
                        }
                    if RGAdFilter.isSeparator(text(previous)) || endsEarlierBody {
                        lower = previous.upper
                        break
                    }
                }
            }
            if index + 1 < lines.count {
                for next in lines[(index + 1)...] {
                    if RGAdFilter.isSeparator(text(next)) {
                        upper = next.lower
                        break
                    }
                    if normalTags(next) {
                        upper = next.lower
                        break
                    }
                }
            }
            let before = RGAdRange(lower, line.lower)
            let after = RGAdRange(line.upper, upper)
            if categoryDeclaration {
            } else if labelOnly && !empty(before) && !empty(after) {
                guard hashtag.numberOfMatches(in: text(line), range: NSRange(location: 0, length: line.upper - line.lower)) == 1 else {
                    continue
                }
                let nextBody =
                    blocks.first(where: { $0.contains(marker) && !empty(RGAdRange(line.upper, $0.upper)) })
                    ?? blocks.first(where: { $0.lower >= line.upper && !empty($0) })
                guard let nextBody else { continue }
                lower = line.lower
                upper = min(upper, nextBody.upper)
            } else if labelOnly && (empty(before) || empty(after)) {
            } else if onlyTagsAndDecoration(prefix),
                let block = blocks.first(where: { $0.contains(marker) })
            {
                lower = max(lower, inlineHead ? sentence.lower : line.lower)
                upper = min(upper, inlineHead ? sentence.upper : block.upper)
            } else if onlyTagsAndDecoration(suffix) {
                lower = max(lower, sentence.lower)
                upper = min(upper, sentence.upper)
            } else {
                continue
            }
            let range = RGAdRange(lower, upper)
            guard rgAdValid(range, boundaries: boundaries),
                !input.entities.contains(where: { entity in
                    guard entity.range.intersects(range) else { return false }
                    if entity.kind == .code {
                        guard entity.range.lower >= 0, entity.range.upper <= source.length else { return true }
                        return !RGAdFilter.isInlineCodeLabel(entity, source: source)
                            && !(range == RGAdRange(0, source.length) && isTextLabel(entity, source: source))
                    }
                    if [.link, .mention, .customEmoji].contains(entity.kind) { return !range.contains(entity.range) }
                    return false
                })
            else { continue }
            if !result.contains(range) { result.append(range) }
        }
        return result
    }
}
