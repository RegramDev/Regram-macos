import Foundation

public struct RGAdRange: Codable, Equatable, Hashable {
    public let lower: Int
    public let upper: Int
    public init(_ lower: Int, _ upper: Int) {
        self.lower = lower
        self.upper = upper
    }
    public var nsRange: NSRange { NSRange(location: lower, length: max(0, upper - lower)) }
    public func intersects(_ other: Self) -> Bool { lower < other.upper && other.lower < upper }
    public func contains(_ other: Self) -> Bool { lower <= other.lower && upper >= other.upper }
}

public struct RGAdEntity: Codable, Equatable, Hashable {
    public enum Kind: String, Codable { case format, link, mention, customEmoji, code, quote }
    public let range: RGAdRange
    public let kind: Kind
    public let value: String?
    public init(range: RGAdRange, kind: Kind, value: String? = nil) {
        self.range = range
        self.kind = kind
        self.value = value
    }
}

public struct RGAdButton: Codable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let target: String?
    public init(id: String, title: String, target: String? = nil) {
        self.id = id
        self.title = title
        self.target = target
    }
}

public struct RGAdInput: Codable, Equatable, Hashable {
    public let text: String
    public let peerId: Int64?
    public let entities: [RGAdEntity]
    public let buttons: [[RGAdButton]]
    public let hasMedia: Bool
    public let previewTarget: String?
    public init(
        text: String, peerId: Int64? = nil, entities: [RGAdEntity] = [], buttons: [[RGAdButton]] = [], hasMedia: Bool = false,
        previewTarget: String? = nil
    ) {
        self.text = text
        self.peerId = peerId
        self.entities = entities
        self.buttons = buttons
        self.hasMedia = hasMedia
        self.previewTarget = previewTarget
    }
}

public struct RGAdRule: Codable, Equatable {
    public enum Kind: String, Codable { case literal, regex, target }
    public enum Scope: String, Codable { case match, paragraph }
    public let pattern: String
    public let kind: Kind
    public let scope: Scope
    public let peerId: Int64?
    public init(_ pattern: String, kind: Kind = .literal, scope: Scope = .paragraph, peerId: Int64? = nil) {
        self.pattern = pattern
        self.kind = kind
        self.scope = scope
        self.peerId = peerId
    }
}

public struct RGAdPrediction: Codable, Equatable {
    public let range: RGAdRange
    public let confidence: Double
    public init(range: RGAdRange, confidence: Double) {
        self.range = range
        self.confidence = confidence
    }
}

public struct RGAdProjection: Codable, Equatable {
    public enum Disposition: String, Codable { case keep, trim, hide }
    public let disposition: Disposition
    public let text: String
    public let entities: [RGAdEntity]
    public let buttons: [[RGAdButton]]
    public let removedRanges: [RGAdRange]
    public let removedButtonIds: [String]
    public let hideLinkPreview: Bool

    public init(
        disposition: Disposition, text: String, entities: [RGAdEntity], buttons: [[RGAdButton]], removedRanges: [RGAdRange],
        removedButtonIds: [String], hideLinkPreview: Bool
    ) {
        self.disposition = disposition
        self.text = text
        self.entities = entities
        self.buttons = buttons
        self.removedRanges = removedRanges
        self.removedButtonIds = removedButtonIds
        self.hideLinkPreview = hideLinkPreview
    }
}

public enum RGAdFilterError: Error, Equatable {
    case invalidInput, invalidModel, unsupportedTokenizer, inputTooLong, invalidPrediction, budgetExceeded
}

func rgAdBoundaries(_ text: String) -> Set<Int> {
    var result: Set<Int> = [0]
    var offset = 0
    for character in text {
        offset += String(character).utf16.count
        result.insert(offset)
    }
    return result
}

func rgAdValid(_ range: RGAdRange, boundaries: Set<Int>) -> Bool {
    range.lower >= 0 && range.upper > range.lower && boundaries.contains(range.lower) && boundaries.contains(range.upper)
}
