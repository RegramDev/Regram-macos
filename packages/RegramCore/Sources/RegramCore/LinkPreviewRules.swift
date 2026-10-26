import Foundation

public enum RGLinkPreviewRules {
    public static let didChangeNotification = Notification.Name("RGLinkPreviewRulesDidChange")
    public static let defaultXHost = "fixupx.com"
    public static let defaultInstagramHost = "ddinstagram.com"

    public static func isValidHost(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.count <= 253, value.contains("."), !value.hasSuffix("."), !value.contains(":") else { return false }
        return value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 }
        }
    }

    public static func repair(_ original: String, enabled: Bool, xHost: String, instagramHost: String) -> String {
        guard enabled else { return original }
        let qualified = original.contains("://") ? original : "https://" + original
        guard var components = URLComponents(string: qualified),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              components.user == nil, components.password == nil, let host = components.host?.lowercased() else { return original }
        let replacement: String
        switch host {
        case "x.com", "www.x.com", "twitter.com", "www.twitter.com": replacement = xHost
        case "instagram.com", "www.instagram.com": replacement = instagramHost
        default: return original
        }
        let normalized = replacement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidHost(normalized), normalized != host else { return original }
        components.scheme = "https"
        components.host = normalized
        components.port = nil
        return components.string ?? original
    }

}
