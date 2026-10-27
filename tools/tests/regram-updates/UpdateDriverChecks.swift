import Cocoa
import CryptoKit
import NativeSparkle
import SwiftSignalKit

private final class ReleaseURLProtocol: URLProtocol {
    static var status = 200
    static var payload = Data()
    static var requestCount = 0
    static var stoppedCount = 0
    static var holdResponses = false
    static var waiting: [ReleaseURLProtocol] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        DispatchQueue.main.async {
            precondition(self.request.url == updateFeedURL)
            precondition(self.request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
            Self.requestCount += 1
            if Self.holdResponses {
                Self.waiting.append(self)
            } else {
                self.respond(status: Self.status, payload: Self.payload)
            }
        }
    }

    override func stopLoading() {
        DispatchQueue.main.async { Self.stoppedCount += 1 }
    }

    func respond(status: Int, payload: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private let releaseTestSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ReleaseURLProtocol.self]
    return URLSession(configuration: configuration)
}()

private let resourcesQueue = DispatchQueue(label: "Regram.Update.Tests")
private var downloadStarts: [ObjectIdentifier] = []
private var extractionStarts: [ObjectIdentifier] = []
private var installStarts: [(ObjectIdentifier, Bool, Bool)] = []
private func updateString(_ key: String) -> String { key }
private func recordDownloadStart(_ current: ExternalUpdateDriver) { downloadStarts.append(ObjectIdentifier(current)) }
private func recordExtraction(_ current: ExternalUpdateDriver) { extractionStarts.append(ObjectIdentifier(current)) }
private func recordInstall(_ current: ExternalUpdateDriver, relaunch: Bool, showUI: Bool) { installStarts.append((ObjectIdentifier(current), relaunch, showUI)) }

private let testHostBundle: Bundle = {
    let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("RegramUpdateHost-" + UUID().uuidString + ".app")
    try! FileManager.default.createDirectory(at: path.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let info: [String: Any] = ["CFBundleIdentifier": "test.Regram.Update", "CFBundleName": "Regram", "CFBundleVersion": "283369", "CFBundleShortVersionString": "13.1.0"]
    let data = try! PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try! data.write(to: path.appendingPathComponent("Contents/Info.plist"))
    return Bundle(url: path)!
}()

private func waitUntil(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(condition(), "Timed out waiting for the update driver")
}

private func drainCallbacks() {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}

private func releaseData(build: Int = 283370, validDigest: Bool = true) -> Data {
    let name = "Regram-13.1.0-\(build)-\(RegramUpdateArchitecture.current.rawValue).dmg"
    let asset: [String: Any] = ["name": name, "browser_download_url": "https://github.com/RegramDev/Regram-macos/releases/download/v\(build)/" + name, "size": 3, "state": "uploaded", "digest": validDigest ? "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" : "sha256:invalid"]
    return try! JSONSerialization.data(withJSONObject: ["tag_name": "v\(build)", "draft": false, "prerelease": false, "body": "Fixes", "assets": [asset]])
}

private func resetFixture(automaticCheck: Bool = false, automaticDownload: Bool = false) {
    disposable.set(nil)
    cancelStagedUpdate()
    driver = nil
    updateState { _ in initialState }
    var settings = RegramUpdateSettings()
    settings.automaticCheck = automaticCheck
    settings.automaticDownload = automaticDownload
    settings.installOnQuit = true
    settings.save()
    updaterStarted = false
    ReleaseURLProtocol.status = 200
    ReleaseURLProtocol.payload = releaseData()
    ReleaseURLProtocol.holdResponses = false
    ReleaseURLProtocol.waiting.removeAll()
    downloadStarts.removeAll()
    extractionStarts.removeAll()
    installStarts.removeAll()
}

private func hasAvailableUpdate() -> Bool {
    if case .hasUpdate = stateValue.with({ $0.loadingState }) { return true }
    return false
}

private func hasFailedUpdate() -> Bool {
    if case .failed = stateValue.with({ $0.loadingState }) { return true }
    return false
}

@main
struct UpdateDriverChecks {
    static func main() throws {
        defer {
            disposable.set(nil)
            driver = nil
            cancelStagedUpdate()
            try? FileManager.default.removeItem(at: testHostBundle.bundleURL)
            UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
        }
        try checkArchiveChecksum()
        try checkSignatureChain()
        checkManualRetryWithAutomaticChecksDisabled()
        checkManualIntentDuringAutomaticCheck(download: false)
        checkManualIntentDuringAutomaticCheck(download: true)
        checkAutomaticDownloadAndDuplicateActions()
        try checkDownloadVerificationBeforeExtraction()
        checkDisablingAnAutomaticCheckCancelsIt()
        checkOldDriverCallbacksCannotOverwriteNewState()
        checkReadyUpdateSurvivesFailedStaging()
        checkManualCheckCanFindANewerReadyUpdate()
        checkQuitInstallationStartsSynchronously()
        print("Native update driver checks passed: checksum, signature chain, manual retry, preferences, cancellation, stale callbacks, staging, synchronous quit installation")
    }

    static func checkArchiveChecksum() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        try Data("abc".utf8).write(to: file)
        precondition(updateArchiveMatchesSHA256(at: file.path, expectedSHA256: expected, expectedSize: 3))
        precondition(!updateArchiveMatchesSHA256(at: file.path, expectedSHA256: expected, expectedSize: 2))
        precondition(!updateArchiveMatchesSHA256(at: file.path, expectedSHA256: expected, expectedSize: 4))
        precondition(!updateArchiveMatchesSHA256(at: file.path, expectedSHA256: String(repeating: "0", count: 64), expectedSize: 3))
        precondition(!updateArchiveMatchesSHA256(at: file.path + ".missing", expectedSHA256: expected, expectedSize: 3))
        let large = Data(repeating: 0x7f, count: 3 * 1024 * 1024 + 17)
        try large.write(to: file)
        let digest = SHA256.hash(data: large).map { String(format: "%02x", $0) }.joined()
        precondition(updateArchiveMatchesSHA256(at: file.path, expectedSHA256: digest, expectedSize: UInt64(large.count)))
    }

    static func checkSignatureChain() throws {
        let installed = URL(fileURLWithPath: "/Applications/Regram.app")
        guard FileManager.default.fileExists(atPath: installed.path) else { return }
        try SUCodeSigningVerifier.codeSignature(atBundleURL: installed, matchesSignatureAtBundleURL: installed)
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        var rejected = false
        do {
            try SUCodeSigningVerifier.codeSignature(atBundleURL: installed, matchesSignatureAtBundleURL: calculator)
        } catch {
            rejected = true
        }
        precondition(rejected)
    }

    static func checkManualRetryWithAutomaticChecksDisabled() {
        resetFixture()
        let count = ReleaseURLProtocol.requestCount
        startRegramUpdater()
        drainCallbacks()
        precondition(ReleaseURLProtocol.requestCount == count && driver == nil)
        ReleaseURLProtocol.status = 404
        regramCheckForUpdates()
        waitUntil(hasFailedUpdate)
        let failed = driver!
        precondition(failed.finished)
        ReleaseURLProtocol.status = 200
        regramCheckForUpdates()
        waitUntil(hasAvailableUpdate)
        precondition(driver !== failed)
        precondition(downloadStarts.isEmpty)
        ReleaseURLProtocol.payload = releaseData(build: 283369)
        regramCheckForUpdates()
        waitUntil { if case .uptodate = stateValue.with({ $0.loadingState }) { return true }; return false }
        precondition(downloadStarts.isEmpty)
    }

    static func checkAutomaticDownloadAndDuplicateActions() {
        resetFixture(automaticCheck: true, automaticDownload: true)
        startRegramUpdater()
        waitUntil { downloadStarts.count == 1 }
        let current = driver!
        current.downloadUpdate()
        current.didFindValidUpdate()
        current.installWhenQuitting()
        precondition(downloadStarts.count == 1)
        precondition(installStarts.isEmpty)
        let count = ReleaseURLProtocol.requestCount
        startRegramUpdater()
        drainCallbacks()
        precondition(ReleaseURLProtocol.requestCount == count)
        resetFixture()
        regramCheckForUpdates(download: true)
        waitUntil { downloadStarts.count == 1 }
    }

    static func checkManualIntentDuringAutomaticCheck(download: Bool) {
        resetFixture(automaticCheck: true, automaticDownload: false)
        ReleaseURLProtocol.holdResponses = true
        let count = ReleaseURLProtocol.requestCount
        startRegramUpdater()
        waitUntil { ReleaseURLProtocol.waiting.count == 1 }
        let current = driver!
        precondition(current.isCheckingAutomatically)
        regramCheckForUpdates(download: download)
        precondition(driver === current && current.checkWasManual && current.requestedDownload == download)
        if download {
            regramCheckForUpdates()
            precondition(current.requestedDownload)
        }
        changeUpdateSettings { $0.automaticCheck = false }
        precondition(driver === current && !current.finished && !current.isCheckingAutomatically)
        ReleaseURLProtocol.waiting[0].respond(status: 200, payload: releaseData())
        if download {
            waitUntil { downloadStarts.count == 1 }
        } else {
            waitUntil(hasAvailableUpdate)
            precondition(downloadStarts.isEmpty)
        }
        precondition(ReleaseURLProtocol.requestCount == count + 1)
    }

    static func checkDisablingAnAutomaticCheckCancelsIt() {
        resetFixture(automaticCheck: true, automaticDownload: true)
        ReleaseURLProtocol.holdResponses = true
        startRegramUpdater()
        waitUntil { !ReleaseURLProtocol.waiting.isEmpty }
        let previous = driver!
        changeUpdateSettings { $0.automaticCheck = false }
        precondition(driver == nil && previous.finished)
        previous.didFindValidUpdate()
        drainCallbacks()
        precondition(downloadStarts.isEmpty)
        if case .nonInited = stateValue.with({ $0.loadingState }) {} else { preconditionFailure("A canceled check changed the UI") }
    }

    static func checkDownloadVerificationBeforeExtraction() throws {
        for content in ["abd", "abc"] {
            resetFixture()
            regramCheckForUpdates()
            waitUntil(hasAvailableUpdate)
            let current = driver!
            let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try Data(content.utf8).write(to: directory.appendingPathComponent("update.dmg"))
            DispatchQueue.global().async {
                current.downloaderDidSetDestinationName("update.dmg", temporaryDirectory: directory.path)
                current.downloaderDidFinish(withTemporaryDownloadData: nil)
            }
            if content == "abc" {
                waitUntil { extractionStarts.count == 1 }
                precondition(!current.finished)
            } else {
                waitUntil(hasFailedUpdate)
                precondition(current.finished && extractionStarts.isEmpty)
                precondition(!FileManager.default.fileExists(atPath: directory.path))
            }
        }
    }

    static func checkOldDriverCallbacksCannotOverwriteNewState() {
        resetFixture()
        regramCheckForUpdates()
        waitUntil(hasAvailableUpdate)
        let previous = driver!
        regramCheckForUpdates()
        waitUntil(hasAvailableUpdate)
        precondition(previous !== driver && previous.finished)
        previous.unarchiverDidFinish(nil)
        previous.downloaderDidReceiveExpectedContentLength(123)
        previous.downloaderDidReceiveData(ofLength: 20)
        previous.downloaderDidFailWithError(NSError(domain: "test", code: 1))
        previous.didNotFindUpdate()
        previous.didFindValidUpdate()
        precondition(hasAvailableUpdate() && downloadStarts.isEmpty)
    }

    private static func makeReadyUpdate() -> ExternalUpdateDriver {
        resetFixture()
        regramCheckForUpdates()
        waitUntil(hasAvailableUpdate)
        let current = driver!
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try! Data("abc".utf8).write(to: directory.appendingPathComponent("update.dmg"))
        current.downloaderDidSetDestinationName("update.dmg", temporaryDirectory: directory.path)
        current.downloaderDidFinish(withTemporaryDownloadData: nil)
        waitUntil { extractionStarts.count == 1 }
        current.unarchiverDidFinish(nil)
        return current
    }

    static func checkReadyUpdateSurvivesFailedStaging() {
        let current = makeReadyUpdate()
        ReleaseURLProtocol.status = 503
        regramCheckForUpdates()
        waitUntil { stagedDriver == nil }
        precondition(driver === current && !current.finished)
        if case .readyToInstall = stateValue.with({ $0.loadingState }) {} else { preconditionFailure("Lost a prepared update") }
    }

    static func checkManualCheckCanFindANewerReadyUpdate() {
        let current = makeReadyUpdate()
        ReleaseURLProtocol.payload = releaseData(build: 283371)
        regramCheckForUpdates()
        waitUntil(hasAvailableUpdate)
        precondition(driver !== current && current.finished && stagedDriver == nil)
        precondition(driver?.updateItem.versionString == "283371")
        precondition(downloadStarts.isEmpty)
    }

    static func checkQuitInstallationStartsSynchronously() {
        let current = makeReadyUpdate()
        changeUpdateSettings { $0.installOnQuit = false }
        updateAppIfNeeded()
        precondition(installStarts.isEmpty)
        changeUpdateSettings { $0.installOnQuit = true }
        updateAppIfNeeded()
        precondition(installStarts.count == 1)
        precondition(installStarts[0].0 == ObjectIdentifier(current) && !installStarts[0].1 && !installStarts[0].2)
        updateAppIfNeeded()
        current.installWhenQuitting()
        precondition(installStarts.count == 1)
    }
}
