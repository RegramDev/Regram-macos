import Foundation

public enum RegramDataResetScope {
    public static let bundleIdentifier = "app.regram.macos"

    public static func ownsAppGroupIdentifier(_ identifier: String) -> Bool {
        !identifier.contains("/") && !identifier.contains("\\") && (identifier == bundleIdentifier || identifier.hasSuffix("." + bundleIdentifier))
    }

    public static func applicationDirectory(root: URL) -> URL? {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let directory = resolvedRoot.appendingPathComponent(bundleIdentifier, isDirectory: true).standardizedFileURL
        guard directory.deletingLastPathComponent().path == resolvedRoot.path,
              directory.resolvingSymlinksInPath().path == directory.path else { return nil }
        return directory
    }

    public static func groupDirectory(_ directory: URL, identifier: String) -> URL? {
        let candidate = directory.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(identifier, isDirectory: true).standardizedFileURL
        guard ownsAppGroupIdentifier(identifier), directory.lastPathComponent == identifier,
              candidate.resolvingSymlinksInPath().path == candidate.path else { return nil }
        return candidate
    }

    public static func ownsKeychainService(_ service: String) -> Bool {
        if service == bundleIdentifier + ".Regram.Services" { return true }
        let parts = service.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return false }
        return ["stable", "appstore", "beta", "debug"].contains { parts[0] == "org.telegram.scoped." + bundleIdentifier + "." + $0 }
    }
}
