import Foundation
import XCTest
@testable import RegramCore

final class RegramUpdatePolicyTests: XCTestCase {
    private func release(names: [String], digest: String? = "sha256:" + String(repeating: "a", count: 64), url: String? = nil, draft: Bool = false, prerelease: Bool = false, size: Int64 = 1024, state: String = "uploaded") throws -> Data {
        let assets: [[String: Any]] = names.map { name in
            var asset: [String: Any] = ["name": name, "browser_download_url": url ?? "https://github.com/RegramDev/Regram-macos/releases/download/v283370/" + name, "size": size, "state": state]
            if let digest { asset["digest"] = digest }
            return asset
        }
        return try JSONSerialization.data(withJSONObject: ["tag_name": "v283370", "draft": draft, "prerelease": prerelease, "body": "Fix <input> & paste", "assets": assets])
    }

    func testSplitPackagesMatchTheRunningArchitecture() throws {
        let data = try release(names: ["Regram-13.1.0-283370-x86_64.dmg", "Regram-13.1.0-283370-Universal.dmg", "Regram-13.1.0-283370-arm64.dmg"])
        for architecture in [RegramUpdateArchitecture.arm64, .x86_64] {
            let update = try XCTUnwrap(RegramUpdatePolicy.release(from: data, currentBuild: 283369, architecture: architecture))
            XCTAssertTrue(update.downloadURL.lastPathComponent.hasSuffix(architecture.rawValue + ".dmg"))
            XCTAssertEqual(update.build, 283370)
            XCTAssertEqual(update.sha256, String(repeating: "a", count: 64))
            XCTAssertTrue(String(decoding: update.appcastData, as: UTF8.self).contains("sparkle:version=\"283370\""))
        }
    }

    func testUniversalFallbackAndOlderVersions() throws {
        let data = try release(names: ["Regram-13.1.0-283370-Universal.dmg"])
        XCTAssertNotNil(try RegramUpdatePolicy.release(from: data, currentBuild: 283369, architecture: .arm64))
        XCTAssertNil(try RegramUpdatePolicy.release(from: data, currentBuild: 283370, architecture: .arm64))
        XCTAssertNil(try RegramUpdatePolicy.release(from: data, currentBuild: 283371, architecture: .arm64))
    }

    func testNativeDiskImageIsPreferredRegardlessOfAssetOrder() throws {
        let names = ["Regram-13.1.0-283370-Universal.dmg", "Regram-13.1.0-283370-arm64.zip", "Regram-13.1.0-283370-arm64.dmg"]
        for ordered in [names, Array(names.reversed())] {
            let update = try XCTUnwrap(RegramUpdatePolicy.release(from: release(names: ordered), currentBuild: 283369, architecture: .arm64))
            XCTAssertEqual(update.downloadURL.lastPathComponent, "Regram-13.1.0-283370-arm64.dmg")
        }
    }

    func testIncompleteLatestReleaseCannotFallBackToAnOlderBuild() throws {
        let names = ["Regram-13.1.0-283369-arm64.dmg", "Regram-13.1.0-283370-x86_64.dmg"]
        XCTAssertThrowsError(try RegramUpdatePolicy.release(from: release(names: names), currentBuild: 283368, architecture: .arm64)) { error in
            XCTAssertEqual(error as? RegramUpdatePolicy.ValidationError, .noCompatibleAsset)
        }
    }

    func testWrongArchitectureAndUntrustedDownloadsAreRejected() throws {
        let name = "Regram-13.1.0-283370-arm64.dmg"
        XCTAssertThrowsError(try RegramUpdatePolicy.release(from: release(names: [name]), currentBuild: 283369, architecture: .x86_64))
        let validURL = "https://github.com/RegramDev/Regram-macos/releases/download/v283370/" + name
        for url in ["http://github.com/RegramDev/Regram-macos/releases/download/v283370/" + name, "https://github.com/other/Regram-macos/releases/download/v283370/" + name, "https://example.com/" + name, "https://github.com/RegramDev/Regram-macos/releases/download/old/" + name, validURL + "?token=other", validURL + "#fragment", "https://user@github.com/RegramDev/Regram-macos/releases/download/v283370/" + name, "https://github.com:443/RegramDev/Regram-macos/releases/download/v283370/" + name, validURL.replacingOccurrences(of: name, with: "Regram.dmg")] {
            XCTAssertThrowsError(try RegramUpdatePolicy.release(from: release(names: [name], url: url), currentBuild: 283369, architecture: .arm64))
        }
    }

    func testMissingOrInvalidChecksumsAreRejected() throws {
        for digest in [nil, "sha256:invalid", "sha256:" + String(repeating: "z", count: 64)] as [String?] {
            XCTAssertThrowsError(try RegramUpdatePolicy.release(from: release(names: ["Regram-13.1.0-283370-arm64.dmg"], digest: digest), currentBuild: 283369, architecture: .arm64))
        }
    }

    func testDraftAndPrereleaseAreSkipped() throws {
        let names = ["Regram-13.1.0-283370-arm64.dmg"]
        XCTAssertNil(try RegramUpdatePolicy.release(from: release(names: names, draft: true), currentBuild: 283369, architecture: .arm64))
        XCTAssertNil(try RegramUpdatePolicy.release(from: release(names: names, prerelease: true), currentBuild: 283369, architecture: .arm64))
    }

    func testPartialUploadsEmptyFilesAndUnrelatedAssetsAreRejected() throws {
        let names = ["Regram-13.1.0-283370-arm64.dmg"]
        XCTAssertThrowsError(try RegramUpdatePolicy.release(from: release(names: names, size: 0), currentBuild: 283369, architecture: .arm64))
        XCTAssertThrowsError(try RegramUpdatePolicy.release(from: release(names: names, state: "new"), currentBuild: 283369, architecture: .arm64))
        XCTAssertThrowsError(try RegramUpdatePolicy.release(from: release(names: ["Telegram.dmg", "Regram-13.1.0-283370-arm64.ipa", "Regram-13.1.0-283370-arm64.dmg.sig"]), currentBuild: 283369, architecture: .arm64))
        XCTAssertThrowsError(try RegramUpdatePolicy.release(from: Data("{}".utf8), currentBuild: 283369, architecture: .arm64))
    }

    func testAutomaticUpdatePreferencesPersist() throws {
        let suite = "RegramUpdatePolicyTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = RegramUpdateSettings(defaults: defaults)
        XCTAssertTrue(settings.automaticCheck && settings.automaticDownload && settings.installOnQuit)
        settings.automaticCheck = false
        settings.automaticDownload = false
        settings.installOnQuit = false
        settings.save(defaults: defaults)
        XCTAssertEqual(RegramUpdateSettings(defaults: defaults), settings)
    }
}
