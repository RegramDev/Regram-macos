import Foundation

public final class RegramAccountScope {
    public static let shared = RegramAccountScope()
    private let lock = NSLock()
    private let accounts = NSMapTable<AnyObject, NSNumber>(keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)

    public init() {}

    public func bind(_ object: AnyObject, accountId: Int64) {
        lock.lock()
        accounts.setObject(NSNumber(value: accountId), forKey: object)
        lock.unlock()
    }

    public func accountId(for object: AnyObject) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        return accounts.object(forKey: object)?.int64Value
    }

    public func settings(for object: AnyObject) -> RegramAccountSettings {
        guard let id = accountId(for: object) else { return RegramAccountSettings() }
        return RegramPreferences.shared.settings(accountId: id)
    }
}

public func regramSharedDefaults() -> UserDefaults {
    guard let team = Bundle.main.object(forInfoDictionaryKey: "RegramTeamIdentifier") as? String, !team.isEmpty, !team.contains("$("),
          let group = Bundle.main.object(forInfoDictionaryKey: "RegramApplicationGroup") as? String,
          !group.isEmpty, !group.contains("$("),
          let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
          FileManager.default.isWritableFile(atPath: directory.path),
          let defaults = UserDefaults(suiteName: group) else { return .standard }
    return defaults
}
