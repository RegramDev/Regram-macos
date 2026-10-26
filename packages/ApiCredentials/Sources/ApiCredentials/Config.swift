import Cocoa

public final class ApiEnvironment {
    public static let apiId: Int32 = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RegramApiId") as? String,
              let id = Int32(value), id > 0 else {
            preconditionFailure("Configure REGRAM_API_ID in Telegram-Mac/ApiCredentials.local.xcconfig")
        }
        return id
    }()

    public static let apiHash: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RegramApiHash") as? String,
              value.count == 32, value.allSatisfy({ $0.isHexDigit }) else {
            preconditionFailure("Configure REGRAM_API_HASH in Telegram-Mac/ApiCredentials.local.xcconfig")
        }
        return value
    }()
    
    public static var bundleId: String {
        return Bundle.main.object(forInfoDictionaryKey: "RegramRootBundleIdentifier") as? String ?? "app.regram.macos"
    }
    public static var teamId: String {
        return Bundle.main.object(forInfoDictionaryKey: "RegramTeamIdentifier") as? String ?? ""
    }
    
    
    
    private static let dataRootURL: URL? = {
        let manager = FileManager.default
        let group = teamId.isEmpty ? nil : manager.containerURL(forSecurityApplicationGroupIdentifier: ApiEnvironment.group)
        let local = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent(bundleId, isDirectory: true)
        for candidate in [group, local].compactMap({ $0 }) {
            do {
                try manager.createDirectory(at: candidate, withIntermediateDirectories: true)
                if manager.isWritableFile(atPath: candidate.path) { return candidate }
            } catch {}
        }
        return nil
    }()

    public static var containerURL: URL? {
        guard let directory = dataRootURL?.appendingPathComponent(prefix) else { return nil }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); return directory }
        catch { return nil }
    }
    
    public static func migrate() {
        if let containerURL = containerURL, let legacy = legacyContainerURL, let sequence = FileManager.default.enumerator(atPath: legacy.path) {
            let contents = try? FileManager.default.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil, options: [])
            if let contents = contents, !contents.isEmpty {
                return
            }
            for value in sequence {
                if let value = value as? String {
                    if !prefixList.contains(value) {
                        try? FileManager.default.moveItem(at: legacy.appendingPathComponent(value), to: containerURL.appendingPathComponent(value))
                    }
                }
            }
        }
    }
    
    public static var legacyContainerURL: URL? { dataRootURL }
    
    public static var group: String {
        return Bundle.main.object(forInfoDictionaryKey: "RegramApplicationGroup") as? String ?? (teamId.isEmpty ? bundleId : teamId + "." + bundleId)
    }
    
    public static var appData: Data {
        let apiData = evaluateApiData() ?? ""
        let dict:[String: String] = ["bundleId": bundleId, "data": apiData]
        return try! JSONSerialization.data(withJSONObject: dict, options: [])
    }
    public static var language: String {
        return "macos"
    }
    
    public static var prefixList:[String] {
        return ["debug", "stable", "appstore", "beta"]
    }
    
    public static var prefix: String {
        var prefix: String = ""
        switch Configuration.value(for: .source) {
        case "DEBUG":
            prefix = "debug"
        case "STABLE":
            prefix = "stable"
        case "APP_STORE":
            prefix = "appstore"
        default:
            prefix = "beta"
        }
        return prefix
    }
    
    public static var version: String {
        var suffix: String = ""
        
        suffix = Configuration.value(for: .source) ?? "DEBUG"
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? ""
        return "\(shortVersion) \(suffix)"
    }
    
}



