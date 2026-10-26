import Foundation

public struct RegramRevokedMarker: Equatable {
    public enum Style: String, CaseIterable {
        case icon, text, none
    }

    public var style: Style
    public var text: String
    public var color: String

    public init(style: Style = .icon, text: String = "", color: String = "") {
        self.style = style
        self.text = text
        self.color = color
    }

    public init(settings: RegramAccountSettings) {
        self.init(style: Style(rawValue: settings["revokedMarkerStyle"].string) ?? .icon, text: settings["revokedMarkerText"].string, color: settings["revokedMarkerColor"].string)
    }

    public static func normalizedText(_ value: String) -> String {
        var cleaned = String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && ![0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069].contains($0.value) }.prefix(256).map(String.init).joined().prefix(24)).trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.utf8.count > 384 { cleaned.removeLast() }
        return cleaned
    }

    public static func rgb(_ value: String) -> UInt32? {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.utf8.count == 6, hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        return UInt32(hex, radix: 16)
    }

    public func label(defaultText: String) -> String? {
        switch style {
        case .none: return nil
        case .icon: return "🗑\u{FE0E}"
        case .text:
            let cleaned = Self.normalizedText(text)
            return cleaned.isEmpty ? defaultText : cleaned
        }
    }

    public func apply(to settings: inout RegramAccountSettings) {
        settings["revokedMarkerStyle"] = .string(style.rawValue)
        settings["revokedMarkerText"] = .string(Self.normalizedText(text))
        settings["revokedMarkerColor"] = .string(Self.rgb(color).map { String(format: "#%06X", $0) } ?? "")
    }
}
