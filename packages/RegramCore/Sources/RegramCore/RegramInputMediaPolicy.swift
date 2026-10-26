import Foundation

public enum RGMessageDoubleClickAction: String, CaseIterable {
    case disabled
    case sendReaction
    case showReactions
    case reply
    case repeatMessage
    case repeatWithoutQuote
    case translate
    case edit

    public static func resolved(settings: RegramAccountSettings, canEdit: Bool) -> RGMessageDoubleClickAction {
        var action = RGMessageDoubleClickAction(rawValue: settings["messageDoubleTapAction"].string) ?? .sendReaction
        if !canEdit, let override = RGMessageDoubleClickAction(rawValue: settings["messageDoubleTapActionWithoutEditPermission"].string) {
            action = override
        }
        return action == .edit && !canEdit ? .sendReaction : action
    }
}

public struct RGAutomaticInlineBotRule: Equatable {
    public let username: String
    public let patterns: [String]

    public init(username: String, patterns: [String]) {
        self.username = username
        self.patterns = patterns
    }
}

public struct RGAutomaticInlineBotMatch: Equatable {
    public let username: String
    public let query: String
}

public enum RGAutomaticInlineBots {
    public static let rules: [RGAutomaticInlineBotRule] = [
        .init(username: "twitter_loli_bot", patterns: ["https?://(?:www\\.)?(?:twitter|x)\\.com/\\w+/status/\\d+(?:[/?#]\\S*)?"]),
        .init(username: "Pixiv_bot", patterns: ["https?://www\\.pixiv\\.net(?:/\\w+)?/artworks/\\S+"]),
        .init(username: "Music163bot", patterns: ["https?://music\\.163\\.com/song\\?id=\\d+(?:&\\S*)?"]),
        .init(username: "autoivbot", patterns: [
            "https?://www\\.ithome\\.com/\\S+", "https?://(?:[\\w-]+\\.)?v2ex\\.com/t/\\S+",
            "https?://www\\.nodeseek\\.com/\\S+", "https?://linux\\.do/t/topic/\\S+",
            "https?://github\\.com/[\\w-]+/[\\w.\\-]+(?:\\?\\S+)?",
            "https?://(?:www\\.)?instagram\\.com/(?:p|reel)/[\\w-]+/?(?:[?#]\\S*)?",
            "https?://bsky\\.app/profile/\\S+/post/\\S+",
            "https?://www\\.(?:hoyolab|miyoushe)\\.com(?:/\\w+)?/article/\\d+(?:[?#]\\S*)?",
            "https?://m\\.(?:hoyolab|miyoushe)\\.com/\\S+"
        ])
    ]

    public static func match(_ text: String, enabled: Bool) -> RGAutomaticInlineBotMatch? {
        guard enabled, text.utf8.count <= 4096 else { return nil }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: query),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil, components.user == nil, components.password == nil, components.port == nil else { return nil }
        if components.host?.lowercased() == "github.com", components.path.lowercased().hasSuffix(".git") { return nil }
        let range = NSRange(query.startIndex..., in: query)
        for rule in rules {
            for pattern in rule.patterns {
                if let expression = try? NSRegularExpression(pattern: "^(?:" + pattern + ")$", options: [.caseInsensitive]),
                   let match = expression.firstMatch(in: query, range: range), match.range == range {
                    return RGAutomaticInlineBotMatch(username: rule.username, query: query)
                }
            }
        }
        return nil
    }
}

public final class RGAutomaticInlineBotDismissals {
    public static let shared = RGAutomaticInlineBotDismissals()
    private let lock = NSLock()
    private var queries: [String: String] = [:]

    public init() {}

    private func key(accountId: Int64, peerId: Int64, threadId: Int64?) -> String {
        "\(accountId):\(peerId):\(threadId.map(String.init) ?? "")"
    }

    public func dismiss(_ text: String, accountId: Int64, peerId: Int64, threadId: Int64?) {
        lock.lock()
        defer { lock.unlock() }
        if queries.count >= 256 { queries.removeAll() }
        queries[key(accountId: accountId, peerId: peerId, threadId: threadId)] = text
    }

    public func permits(_ text: String, accountId: Int64, peerId: Int64, threadId: Int64?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = key(accountId: accountId, peerId: peerId, threadId: threadId)
        if queries[key] == text { return false }
        queries.removeValue(forKey: key)
        return true
    }

    public func clear(accountId: Int64) {
        lock.lock()
        queries = queries.filter { !$0.key.hasPrefix("\(accountId):") }
        lock.unlock()
    }
}

public enum RGMediaPolicy {
    public static let recentStickerLimits: [Int] = [20, 30, 40, 50, 60, 80, 100, 120, 150, 200]
    public static let pastedPhotoFilenamePrefix = "regram-pasted-photo-"

    public static func isPastedPhoto(path: String) -> Bool {
        URL(fileURLWithPath: path).lastPathComponent.hasPrefix(pastedPhotoFilenamePrefix)
    }

    public static func recentStickerLimit(settings: RegramAccountSettings) -> Int {
        let value = Int(settings["recentStickerLimit"].integer)
        return recentStickerLimits.contains(value) ? value : 20
    }

    public static func photoQuality(settings: RegramAccountSettings, pasted: Bool = false) -> Double {
        pasted ? 1.0 : Double(min(100, max(0, settings["outgoingPhotoQuality"].integer))) / 100.0
    }

    public static func photoMaximumDimension(native: Double, settings: RegramAccountSettings, pasted: Bool = false) -> Double {
        max(native, settings["sendLargePhotos"].bool || pasted ? 2560.0 : native)
    }

    public static func stickerScale(settings: RegramAccountSettings) -> Double {
        Double(min(200, max(0, settings["stickerSize"].integer))) / 100.0
    }
}
