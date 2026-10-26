import Foundation
import Darwin
import SwiftSignalKit
import RegramCore
import MtProtoKit

public struct RegramDNSResult {
    public let addresses: [String]
    public let elapsed: TimeInterval
}

public enum RegramDNSError: Error {
    case invalidDomain, invalidEndpoint, lookupFailed, invalidResponse, timeout
}

public enum RegramDNSDiagnostics {
    public static let failureDidChange = Notification.Name.MTRGDNSFailureChanged

    public static func lastFailure(endpoint: String) -> String? { MTRGDNSDiagnostics.lastFailure(endpoint: endpoint) }

    public static func orderedAddresses(_ addresses: [String], policy: RegramNetworkPolicy.IPVersion) -> [String] {
        MTRGDNSDiagnostics.orderedAddresses(addresses, policy: Int(policy.rawValue))
    }

    public static func resolve(domain: String, ipv6: Bool, endpoint: String? = nil) -> Signal<RegramDNSResult, RegramDNSError> {
        return resolve(domain: domain, ipv6: ipv6, mode: endpoint == nil ? .system : .custom, endpoint: endpoint ?? "")
    }

    static func parse(_ data: Data, ipv6: Bool) throws -> [String] {
        struct Response: Decodable {
            struct Answer: Decodable { let type: Int; let data: String }
            let Status: Int
            let Answer: [Answer]?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data), response.Status == 0 else { throw RegramDNSError.invalidResponse }
        var seen = Set<String>()
        let family = ipv6 ? AF_INET6 : AF_INET
        let type = ipv6 ? 28 : 1
        let addresses = (response.Answer ?? []).filter { $0.type == type }.compactMap { answer -> String? in
            var bytes = [UInt8](repeating: 0, count: 16)
            guard answer.data.withCString({ inet_pton(family, $0, &bytes) }) == 1, seen.insert(answer.data).inserted else { return nil }
            return answer.data
        }
        guard !addresses.isEmpty else { throw RegramDNSError.lookupFailed }
        return addresses
    }

    public static func resolve(domain: String, ipv6: Bool, mode: RegramNetworkPolicy.DNSMode, endpoint: String = "") -> Signal<RegramDNSResult, RegramDNSError> {
        let domain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validDomain(domain) else { return .fail(.invalidDomain) }
        if mode == .custom && !RegramNetworkPolicy.validEndpoint(endpoint) { return .fail(.invalidEndpoint) }
        return Signal { subscriber in
            let signal = MTRGDNSDiagnostics.queryHostname(domain, dohEndpoint: mode == .custom ? endpoint : nil, family: ipv6 ? 6 : 4, useSystemDNS: mode == .system)
            let disposable = signal.start(next: { value in
                guard let result = value as? [String: Any], let addresses = result["addresses"] as? [String], !addresses.isEmpty, let milliseconds = result["milliseconds"] as? NSNumber else {
                    subscriber.putError(.invalidResponse)
                    return
                }
                subscriber.putNext(RegramDNSResult(addresses: addresses, elapsed: milliseconds.doubleValue / 1000))
                subscriber.putCompletion()
            }, error: { _ in subscriber.putError(.lookupFailed) }, completed: {})
            return ActionDisposable { disposable?.dispose() }
        } |> timeout(15, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.timeout))
    }

    public static func validDomain(_ domain: String) -> Bool {
        guard !domain.isEmpty, domain.utf8.count <= 253, domain.rangeOfCharacter(from: .whitespacesAndNewlines) == nil, !domain.contains("://"), !domain.contains("/") else { return false }
        var bytes = [UInt8](repeating: 0, count: 16)
        if domain.withCString({ inet_pton(AF_INET6, $0, &bytes) }) == 1 { return true }
        let labels = domain.hasSuffix(".") ? String(domain.dropLast()).split(separator: ".", omittingEmptySubsequences: false) : domain.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && label.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 95 }
        }
    }
}
