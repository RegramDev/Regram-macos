import Foundation

public struct RGChatPreferences: Codable, Equatable {
    public var formatting: String?
    public var panguSpacing: Bool?
    public init(formatting: String? = nil, panguSpacing: Bool? = nil) { self.formatting = formatting; self.panguSpacing = panguSpacing }
    public var isEmpty: Bool { self.formatting == nil && self.panguSpacing == nil }
    public static func key(accountId: Int64, peerId: Int64) -> String {
        RegramPeerPreferenceKey.isCloudPeer(peerId) ? String(peerId) : "\(accountId):\(peerId)"
    }
}

public enum RegramPeerPreferenceKey {
    private static let legacyTranslationPrefix = "v2:"

    public static func outgoingTranslation(accountId: Int64, peerId: Int64) -> String {
        isCloudPeer(peerId) ? "peer:\(peerId)" : "\(legacyTranslationPrefix)\(accountId):\(peerId)"
    }

    static func isCloudPeer(_ peerId: Int64) -> Bool {
        ((UInt64(bitPattern: peerId) >> 32) & 7) < 3
    }

    static func sharedChatSettings(_ values: [String: RGChatPreferences], legacyAccountId: Int64) -> [String: RGChatPreferences] {
        var values = values
        for key in Array(values.keys) {
            guard let peerId = Int64(key), !isCloudPeer(peerId), let value = values.removeValue(forKey: key) else { continue }
            let scopedKey = RGChatPreferences.key(accountId: legacyAccountId, peerId: peerId)
            if values[scopedKey] == nil { values[scopedKey] = value }
        }
        return sharedValues(values, legacyAccountId: legacyAccountId, prefix: "", key: RGChatPreferences.key)
    }

    static func sharedOutgoingTranslations(_ values: [String: String], legacyAccountId: Int64) -> [String: String] {
        sharedValues(values, legacyAccountId: legacyAccountId, prefix: legacyTranslationPrefix, key: outgoingTranslation)
    }

    private static func sharedValues<Value>(_ values: [String: Value], legacyAccountId: Int64, prefix: String, key: (Int64, Int64) -> String) -> [String: Value] {
        var updated = values
        var migrated: [String: Value] = [:]
        for storedKey in values.keys.sorted() where storedKey.hasPrefix(prefix) {
            let components = storedKey.dropFirst(prefix.count).split(separator: ":")
            guard components.count == 2, let accountId = Int64(components[0]), let peerId = Int64(components[1]), isCloudPeer(peerId) else { continue }
            let sharedKey = key(accountId, peerId)
            let value = updated.removeValue(forKey: storedKey)
            if accountId == legacyAccountId || migrated[sharedKey] == nil { migrated[sharedKey] = value }
        }
        updated.merge(migrated) { current, _ in current }
        return updated
    }
}
