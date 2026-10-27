import Foundation
import RegramCore

private let suite = "RegramLinkMetadataChecks." + UUID().uuidString
private let fixtureDefaults = UserDefaults(suiteName: suite)!
func fixtureSharedDefaults() -> UserDefaults { fixtureDefaults }

@main
struct PreviewURLChecks {
    static func main() {
        defer { fixtureDefaults.removePersistentDomain(forName: suite) }
        let metadata = RegramLinkMetadata.shared
        var settings = RegramAccountSettings()
        settings["fixLinkPreviews"] = .bool(true)
        let cases: [(String, String)] = [
            ("https://m.miyoushe.com/ys/#/article/123", "https://www.miyoushe.pp.ua/ys/article/123"),
            ("https://m.miyoushe.com/ys/?utm_source=share#/article/123", "https://www.miyoushe.pp.ua/ys/article/123"),
            ("https://x.com/example/status/123?utm_source=share&ref=tracking#thread", "https://fixupx.com/example/status/123"),
            ("https://m.moec.top/notes/42?utm_source=feed#top", "https://t.me/iv?rhash=06c9960651c612&url=https://m.moec.top/notes/42"),
            ("https://sir.social/posts/42?utm_source=feed#top", "https://t.me/iv?rhash=f71a01ee06ddcd&url=https://sir.social/posts/42")
        ]
        for (original, expected) in cases {
            expect(metadata.previewUrl(original, settings: settings), expected)
        }
        for (original, _) in cases where original.contains("m.moec.top") || original.contains("sir.social") {
            let transformed = metadata.previewUrl(original, settings: settings)
            let url = URLComponents(string: transformed)!
            let query = Dictionary(uniqueKeysWithValues: url.queryItems!.map { ($0.name, $0.value!) })
            precondition(url.host == "t.me" && url.path == "/iv" && query.count == 2)
            precondition(query["rhash"]?.isEmpty == false && query["url"]?.hasPrefix("https://") == true)
            precondition(!transformed.contains("utm_source") && url.fragment == nil)
        }
        let unmatched = [
            "https://example.org/resource?keep=1#part",
            "https://m.moec.top/profile?keep=1#part",
            "https://x.com.evil.invalid/status/123?keep=1#part"
        ]
        for original in unmatched { expect(metadata.previewUrl(original, settings: settings), original) }
        let invalid = ["https://[invalid]/path", "https://%/path", "javascript:alert(1)", "https://", "https://user:password@x.com/example/status/123?keep=1#part"]
        for original in invalid { expect(metadata.previewUrl(original, settings: settings), original) }
        settings["fixLinkPreviews"] = .bool(false)
        for original in cases.map(\.0) + unmatched + invalid { expect(metadata.previewUrl(original, settings: settings), original) }
        precondition(fixtureDefaults.dictionaryRepresentation().keys.allSatisfy { !$0.hasPrefix("rg.linkMetadata.") })
        print("Production previewUrl checks passed: Miyoushe hash routes, X tracking removal, generated Instant View queries, disabled/unmatched URLs and malformed URL safety; no Telegram engine, network or user cache was used")
    }
    static func expect(_ actual: String, _ expected: String) {
        precondition(actual == expected, "Expected \(expected), received \(actual)")
    }
}
