import Foundation

public struct RegramNetworkPolicy: Equatable {
    public enum IPVersion: Int64, CaseIterable {
        case automatic = 0
        case ipv4Only = 1
        case ipv6Only = 2
        case ipv4 = 4
        case ipv6 = 6

        public var titleKey: String {
            switch self {
            case .automatic: return "NetworkPolicy.Automatic"
            case .ipv4Only: return "NetworkPolicy.IPv4Only"
            case .ipv4: return "NetworkPolicy.IPv4"
            case .ipv6: return "NetworkPolicy.IPv6"
            case .ipv6Only: return "NetworkPolicy.IPv6Only"
            }
        }

        public static var sourceOrder: [Self] { [.automatic, .ipv4Only, .ipv4, .ipv6, .ipv6Only] }
    }

    public enum DNSMode: String, CaseIterable {
        case automatic
        case system
        case custom

        public var titleKey: String {
            switch self {
            case .automatic: return "NetworkPolicy.BuiltInDNS"
            case .system: return "DNSDiagnostics.SystemDNS"
            case .custom: return "NetworkPolicy.DoH"
            }
        }
    }

    public var dnsMode: DNSMode
    public var endpoint: String
    public var ipVersion: IPVersion
    public var disableBackupAddresses: Bool

    public init(settings: RegramAccountSettings) {
        dnsMode = settings["customDoHEnabled"].bool ? .custom : settings["localDNSForProxyHost"].bool ? .system : .automatic
        endpoint = settings["customDoHEndpoint"].string
        ipVersion = IPVersion(rawValue: settings["ipVersionPolicy"].integer) ?? .automatic
        disableBackupAddresses = settings["disableBackupAddresses"].bool
    }

    public func apply(to settings: inout RegramAccountSettings) {
        settings["customDoHEnabled"] = .bool(dnsMode == .custom)
        settings["localDNSForProxyHost"] = .bool(dnsMode == .system)
        settings["customDoHEndpoint"] = .string(endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
        settings["ipVersionPolicy"] = .integer(ipVersion.rawValue)
        settings["disableBackupAddresses"] = .bool(disableBackupAddresses)
    }

    public static func validEndpoint(_ value: String) -> Bool {
        guard value.utf8.count <= 2048 else { return false }
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 2048, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: value), components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false, components.user == nil, components.password == nil,
              components.fragment == nil, components.query == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              components.url != nil else { return false }
        return true
    }

    public var effectiveEndpoint: String? {
        guard dnsMode == .custom else { return nil }
        return Self.validEndpoint(endpoint) ? endpoint.trimmingCharacters(in: .whitespacesAndNewlines) : "invalid-doh-endpoint"
    }
}
