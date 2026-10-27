import Foundation
import NativeSparkle

@main
struct UpdateAppcastChecks {
    static func main() throws {
        for architecture in [RegramUpdateArchitecture.arm64, .x86_64] {
            let name = "Regram-13.1.0-283370-\(architecture.rawValue).dmg"
            let downloadURL = "https://github.com/RegramDev/Regram-macos/releases/download/v283370/" + name
            let data = try JSONSerialization.data(withJSONObject: ["tag_name": "v283370", "draft": false, "prerelease": false, "body": "Fix <input> & paste", "assets": [["name": name, "browser_download_url": downloadURL, "size": 1024, "state": "uploaded", "digest": "sha256:" + String(repeating: "a", count: 64)]]])
            guard let release = try RegramUpdatePolicy.release(from: data, currentBuild: 283369, architecture: architecture) else { fatalError("Missing update") }
            let appcast = SUAppcast()
            appcast.parseAppcastItems(fromXMLData: release.appcastData, error: nil)
            guard let items = appcast.items as? [SUAppcastItem], items.count == 1, let item = items.first else { fatalError("Invalid Sparkle appcast") }
            precondition(item.versionString == "283370")
            precondition(item.displayVersionString == "13.1.0")
            precondition(item.fileURL.absoluteString == downloadURL)
            precondition(item.contentLength == 1024)
            precondition(item.itemDescription.contains("&lt;input&gt; &amp; paste"))
        }
        print("Native Sparkle appcast checks passed for arm64 and x86_64")
    }
}
