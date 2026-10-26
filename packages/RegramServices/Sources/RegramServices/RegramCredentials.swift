import Foundation
import Security

public enum RegramCredentialPurpose: String {
    case translation, summary, transcription
}

public struct RegramKeychainError: Error {
    public let status: OSStatus
}

public final class RegramCredentials {
    public static let shared = RegramCredentials()
    private let service: String

    public init(service: String = (Bundle.main.bundleIdentifier ?? "Regram.macOS") + ".Regram.Services") {
        self.service = service
    }

    public func read(accountId: Int64, purpose: RegramCredentialPurpose) throws -> String {
        var query = baseQuery(accountId, purpose)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw RegramKeychainError(status: status) }
        return value
    }

    public func write(_ value: String, accountId: Int64, purpose: RegramCredentialPurpose) throws {
        let query = baseQuery(accountId, purpose)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw RegramKeychainError(status: status) }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw RegramKeychainError(status: added) }
        } else if status != errSecSuccess { throw RegramKeychainError(status: status) }
    }

    public func clear(accountId: Int64) throws {
        for purpose in [RegramCredentialPurpose.translation, .summary, .transcription] { try write("", accountId: accountId, purpose: purpose) }
    }

    private func baseQuery(_ accountId: Int64, _ purpose: RegramCredentialPurpose) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "\(accountId).\(purpose.rawValue)",
         kSecAttrSynchronizable as String: false]
    }
}
