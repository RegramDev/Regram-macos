import Foundation

public struct RGAdTokenizer {
    private let vocabulary: [String: Int32]
    public let sequenceLength: Int
    private static let url = try! NSRegularExpression(pattern: "https?://[^\\s<>]+|(?:t\\.me|telegram\\.me)/[^\\s<>]+")
    private static let mention = try! NSRegularExpression(pattern: "@[a-zA-Z0-9_]{1,32}")
    private static let number = try! NSRegularExpression(pattern: "[0-9]{5,}")
    private static let chineseSpace = try! NSRegularExpression(pattern: "(?<=[\\u3400-\\u9fff])\\s+(?=[\\u3400-\\u9fff])")
    private static let whitespace = try! NSRegularExpression(pattern: "\\s+")

    public init(vocabulary: String, sequenceLength: Int = 128) throws {
        let words = vocabulary.components(separatedBy: "\n")
        guard (32...512).contains(sequenceLength), words.count >= 1000, words.count <= 100_000,
            words[0] == "[PAD]", words[100] == "[UNK]", words[101] == "[CLS]", words[102] == "[SEP]"
        else { throw RGAdFilterError.unsupportedTokenizer }
        var result: [String: Int32] = [:]
        for (index, word) in words.enumerated() where !word.isEmpty {
            guard result[word] == nil else { throw RGAdFilterError.unsupportedTokenizer }
            result[word] = Int32(index)
        }
        self.vocabulary = result
        self.sequenceLength = sequenceLength
    }

    public static func normalize(_ text: String) -> String {
        var value = String(
            String.UnicodeScalarView(
                text.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars.filter {
                    ![.format, .nonspacingMark, .enclosingMark, .otherSymbol, .modifierSymbol].contains($0.properties.generalCategory)
                }))
        for (regex, replacement) in [(url, " 链接 "), (mention, " 用户 "), (number, " 数字 "), (chineseSpace, ""), (whitespace, " ")] {
            value = regex.stringByReplacingMatches(
                in: value, range: NSRange(location: 0, length: value.utf16.count), withTemplate: replacement)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isChinese(_ value: UInt32) -> Bool {
        (0x4e00...0x9fff).contains(value) || (0x3400...0x4dbf).contains(value) || (0x20000...0x2a6df).contains(value)
            || (0x2a700...0x2b73f).contains(value) || (0x2b740...0x2b81f).contains(value) || (0x2b820...0x2ceaf).contains(value)
            || (0xf900...0xfaff).contains(value) || (0x2f800...0x2fa1f).contains(value)
    }
    private static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (33...47).contains(v) || (58...64).contains(v) || (91...96).contains(v) || (123...126).contains(v)
            || [
                .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation, .finalPunctuation,
                .otherPunctuation,
            ].contains(scalar.properties.generalCategory)
    }

    public func tokens(_ text: String) -> [Int32]? {
        guard text.utf16.count <= 8192 else { return nil }
        let text = Self.normalize(text).decomposedStringWithCanonicalMapping
        var basic: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty {
                basic.append(current)
                current = ""
            }
        }
        for scalar in text.unicodeScalars {
            if scalar.value == 0 || scalar.value == 0xfffd || scalar.properties.generalCategory == .nonspacingMark { continue }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                flush()
            } else if [.control, .format].contains(scalar.properties.generalCategory) {
                continue
            } else if Self.isChinese(scalar.value) || Self.isPunctuation(scalar) {
                flush()
                basic.append(String(scalar))
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        flush()
        var result: [Int32] = []
        for token in basic {
            let scalars = Array(token.unicodeScalars)
            if scalars.count > 100 {
                result.append(100)
                continue
            }
            var start = 0
            var pieces: [Int32] = []
            var failed = false
            while start < scalars.count {
                var end = scalars.count
                var found: Int32?
                while end > start {
                    let piece = (start == 0 ? "" : "##") + String(String.UnicodeScalarView(scalars[start..<end]))
                    if let id = vocabulary[piece] {
                        found = id
                        break
                    }
                    end -= 1
                }
                guard let id = found else {
                    failed = true
                    break
                }
                pieces.append(id)
                start = end
            }
            result += failed ? [100] : pieces
            if result.count > 1024 { return nil }
        }
        return result
    }

    public func windows(_ text: String) -> [[Int32]]? {
        guard let tokens = tokens(text), !tokens.isEmpty else { return nil }
        let capacity = sequenceLength - 2
        var result: [[Int32]] = []
        var start = 0
        while start < tokens.count {
            let end = min(tokens.count, start + capacity)
            var ids: [Int32] = [101] + Array(tokens[start..<end]) + [102]
            ids += Array(repeating: 0, count: sequenceLength - ids.count)
            result.append(ids)
            if end == tokens.count { break }
            start = min(end - 16, max(0, tokens.count - capacity))
        }
        return result
    }
}
