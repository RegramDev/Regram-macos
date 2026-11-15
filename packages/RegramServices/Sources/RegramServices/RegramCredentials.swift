import Foundation
import Security
import RegramCore

public enum RegramCredentialPurpose: String {
    case translation, summary, transcription
}

public struct RegramKeychainError: Error {
    public let status: OSStatus
}

public final class RegramCredentials {
    public static let shared = RegramCredentials()
    private let service: String
    private let lock = NSLock()

    public init(service: String = (Bundle.main.bundleIdentifier ?? "Regram.macOS") + ".Regram.Services") {
        self.service = service
    }

    public func read(purpose: RegramCredentialPurpose) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if let value = try read(scope: "shared", purpose: purpose) { return value }
        guard let accountId = RegramPreferences.shared.legacySettingsAccountId,
              let value = try read(scope: String(accountId), purpose: purpose) else { return "" }
        try write(value, scope: "shared", purpose: purpose)
        return value
    }

    public func write(_ value: String, purpose: RegramCredentialPurpose) throws {
        lock.lock()
        defer { lock.unlock() }
        try write(value.trimmingCharacters(in: .whitespacesAndNewlines), scope: "shared", purpose: purpose)
    }

    public func removeLegacyAccount(_ accountId: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        let isMigrationSource = RegramPreferences.shared.legacySettingsAccountId == accountId
        for purpose in [RegramCredentialPurpose.translation, .transcription, .summary] {
            if isMigrationSource && purpose != .summary,
               try read(scope: "shared", purpose: purpose) == nil { continue }
            let status = SecItemDelete(baseQuery(String(accountId), purpose) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw RegramKeychainError(status: status) }
        }
    }

    private func read(scope: String, purpose: RegramCredentialPurpose) throws -> String? {
        var query = baseQuery(scope, purpose)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw RegramKeychainError(status: status) }
        return value
    }

    private func write(_ value: String, scope: String, purpose: RegramCredentialPurpose) throws {
        let query = baseQuery(scope, purpose)
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

    private func baseQuery(_ scope: String, _ purpose: RegramCredentialPurpose) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "\(scope).\(purpose.rawValue)",
         kSecAttrSynchronizable as String: false]
    }
}
