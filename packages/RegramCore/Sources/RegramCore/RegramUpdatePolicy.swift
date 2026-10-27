import Foundation

public enum RegramUpdateArchitecture: String {
    case arm64
    case x86_64

    public static var current: RegramUpdateArchitecture {
        #if arch(arm64)
        return .arm64
        #else
        return .x86_64
        #endif
    }
}

public struct RegramUpdateRelease: Equatable {
    public let build: Int64
    public let version: String
    public let downloadURL: URL
    public let size: Int64
    public let sha256: String
    public let notes: String

    public var appcastData: Data {
        func escaped(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
        }
        let description = "<pre>" + escaped(notes) + "</pre>"
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Regram</title><item><title>Regram \(escaped(version))</title><description>\(escaped(description))</description><sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion><enclosure url="\(escaped(downloadURL.absoluteString))" length="\(size)" type="application/octet-stream" sparkle:version="\(build)" sparkle:shortVersionString="\(escaped(version))" /></item></channel></rss>
        """
        return Data(xml.utf8)
    }
}

public enum RegramUpdatePolicy {
    public enum ValidationError: Error, Equatable {
        case invalidRelease
        case noCompatibleAsset
        case invalidChecksum
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let body: String?
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int64
        let state: String
        let digest: String?
    }

    public static func release(from data: Data, currentBuild: Int64, architecture: RegramUpdateArchitecture) throws -> RegramUpdateRelease? {
        let release: Release
        do { release = try JSONDecoder().decode(Release.self, from: data) }
        catch { throw ValidationError.invalidRelease }
        guard !release.draft, !release.prerelease else { return nil }
        let pattern = try NSRegularExpression(pattern: "^Regram-([0-9]+(?:\\.[0-9]+)*)-([0-9]+)-(arm64|x86_64|universal)\\.(dmg|zip)$", options: [.caseInsensitive])
        let assets = release.assets.compactMap { asset -> (Asset, String, Int64, String)? in
            let name = asset.name as NSString
            guard asset.state == "uploaded", let match = pattern.firstMatch(in: asset.name, range: NSRange(location: 0, length: name.length)), let build = Int64(name.substring(with: match.range(at: 2))) else { return nil }
            return (asset, name.substring(with: match.range(at: 1)), build, name.substring(with: match.range(at: 3)).lowercased())
        }
        guard let latestBuild = assets.map({ $0.2 }).max() else { throw ValidationError.noCompatibleAsset }
        guard latestBuild > currentBuild else { return nil }
        let latest = assets.filter { $0.2 == latestBuild }.sorted {
            if $0.0.name.lowercased().hasSuffix(".dmg") != $1.0.name.lowercased().hasSuffix(".dmg") {
                return $0.0.name.lowercased().hasSuffix(".dmg")
            }
            return $0.0.name < $1.0.name
        }
        guard let selected = latest.first(where: { $0.3 == architecture.rawValue }) ?? latest.first(where: { $0.3 == "universal" }) else { throw ValidationError.noCompatibleAsset }
        let asset = selected.0
        guard let url = URL(string: asset.browser_download_url), let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.scheme == "https", components.host == "github.com", components.user == nil, components.password == nil, components.port == nil, components.query == nil, components.fragment == nil, url.pathComponents.count == 7, url.pathComponents[1...4].elementsEqual(["RegramDev", "Regram-macos", "releases", "download"]), url.pathComponents[5] == release.tag_name, url.lastPathComponent == asset.name, asset.size > 0 else { throw ValidationError.invalidRelease }
        guard let digest = asset.digest, digest.hasPrefix("sha256:"), digest.count == 71 else { throw ValidationError.invalidChecksum }
        let hash = String(digest.dropFirst(7)).lowercased()
        guard hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw ValidationError.invalidChecksum }
        return RegramUpdateRelease(build: selected.2, version: selected.1, downloadURL: url, size: asset.size, sha256: hash, notes: release.body ?? "")
    }
}

public struct RegramUpdateSettings: Equatable {
    public var automaticCheck: Bool
    public var automaticDownload: Bool
    public var installOnQuit: Bool

    public init(defaults: UserDefaults = .standard) {
        automaticCheck = defaults.object(forKey: "Regram.Updates.AutomaticCheck") as? Bool ?? true
        automaticDownload = defaults.object(forKey: "Regram.Updates.AutomaticDownload") as? Bool ?? true
        installOnQuit = defaults.object(forKey: "Regram.Updates.InstallOnQuit") as? Bool ?? true
    }

    public func save(defaults: UserDefaults = .standard) {
        defaults.set(automaticCheck, forKey: "Regram.Updates.AutomaticCheck")
        defaults.set(automaticDownload, forKey: "Regram.Updates.AutomaticDownload")
        defaults.set(installOnQuit, forKey: "Regram.Updates.InstallOnQuit")
    }
}
