import Foundation

public enum RGLocalGiftAssets {
    public static func directory(account: String, applicationSupport: URL? = nil) -> URL? {
        let parts = account.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, ["live", "test"].contains(String(parts[0])), Int64(parts[1]) != nil,
              let root = applicationSupport ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let app = RegramDataResetScope.applicationDirectory(root: root) else { return nil }
        let directory = app.appendingPathComponent("RegramLocalGifts", isDirectory: true).appendingPathComponent(account, isDirectory: true)
        guard directory.resolvingSymlinksInPath().path == directory.path else { return nil }
        return directory
    }

    public static func prepare(directory: URL) throws {
        guard directory.resolvingSymlinksInPath().path == directory.path else { throw RGLocalGiftsError.storage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard directory.resolvingSymlinksInPath().path == directory.path else { throw RGLocalGiftsError.storage }
    }

    public static func asset(directory: URL, name: String) -> URL? {
        guard name == "empty-pattern.asset" || (name.hasSuffix(".asset") && UUID(uuidString: String(name.dropLast(6))) != nil),
              directory.resolvingSymlinksInPath().path == directory.path else { return nil }
        let file = directory.appendingPathComponent(name)
        guard file.resolvingSymlinksInPath().path == file.path else { return nil }
        return file
    }

    public static func removeAccount(account: String, applicationSupport: URL? = nil) {
        guard let directory = directory(account: account, applicationSupport: applicationSupport) else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
