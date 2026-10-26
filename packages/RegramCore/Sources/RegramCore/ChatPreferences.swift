import Foundation

public struct RGChatPreferences: Codable, Equatable {
    public var formatting: String?
    public var panguSpacing: Bool?
    public init(formatting: String? = nil, panguSpacing: Bool? = nil) { self.formatting = formatting; self.panguSpacing = panguSpacing }
    public var isEmpty: Bool { self.formatting == nil && self.panguSpacing == nil }
    public static func key(accountId: Int64, peerId: Int64) -> String { "\(accountId):\(peerId)" }
}
