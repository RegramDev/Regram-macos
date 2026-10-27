#if !APP_STORE

import Cocoa
import TGUIKit
import SwiftSignalKit
import Sparkle
import CrashRecoveryUI
import RegramCore
import CryptoKit



final class RegramUpdater : NSObject, SUUpdaterPrivate {
    var delegate: SUUpdaterDelegate!
    
    var userAgentString: String!
    
    var httpHeaders: [AnyHashable : Any]!
    
    var decryptionPassword: String!
    
    var sparkleBundle: Bundle!
    
    override init() {
        self.sparkleBundle = Bundle(for: SUUpdateDriver.self)
        self.userAgentString = "Regram-macOS"
        super.init()
    }
}

extension SUAppcastItem {
    var updateText: String {
        var updateText = (itemDescription.html2Attributed?.string ?? itemDescription).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        while let range = updateText.range(of: "   ") {
            updateText = updateText.replacingOccurrences(of: "   ", with: "  ", options: [], range: range)
        }
        updateText = updateText.replacingOccurrences(of: "•", with: "\n•", options: [], range: nil)
        
        if updateText.first == "\n" {
            updateText.removeFirst()
        }
        updateText = updateText.replacingOccurrences(of: "\t", with: "  ", options: [], range: nil)
        return updateText
    }
    
    var versionTitle: String {
        return "\(self.displayVersionString ?? "") (\(self.versionString ?? ""))"
    }
}



enum AppUpdateLoadingState : Equatable {
    case nonInited
    case initializing
    case loading(item:SUAppcastItem, current: Int, total: Int)
    case hasUpdate(SUAppcastItem)
    case readyToInstall(SUAppcastItem)
    case uptodate
    case unarchiving(SUAppcastItem)
    case installing
    case failed(NSError)
}

private let initialState = AppUpdateState(items: [], loadingState: .nonInited)
private let statePromise: ValuePromise<AppUpdateState> = ValuePromise(initialState, ignoreRepeated: true)
private let stateValue = Atomic(value: initialState)

var appUpdateStateSignal: Signal<AppUpdateState, NoError> {
    return statePromise.get()
}

private let updateState:((AppUpdateState)->AppUpdateState) -> Void = { f in
    statePromise.set(stateValue.modify(f))
}
private let updaterSettings = ValuePromise(RegramUpdateSettings(), ignoreRepeated: true)
private let updater = RegramUpdater()

private func updateString(_ key: String) -> String {
    regramLocalizedString(key, languageCode: appCurrentLanguage.primaryLanguage.languageCode)
}

private func changeUpdateSettings(_ change: (inout RegramUpdateSettings) -> Void) {
    var settings = RegramUpdateSettings()
    change(&settings)
    settings.save()
    updaterSettings.set(settings)
    if !settings.automaticDownload || !settings.automaticCheck {
        cancelStagedUpdate()
    }
    if !settings.automaticCheck, driver?.isCheckingAutomatically == true {
        driver = nil
        updateState { _ in initialState }
    }
    resetUpdater()
}
private let currentDriver = Atomic<ObjectIdentifier?>(value: nil)
private var driver: ExternalUpdateDriver? {
    didSet {
        let identifier = driver.map { ObjectIdentifier($0) }
        _ = currentDriver.swap(identifier)
        if oldValue !== driver {
            oldValue?.abortUpdate()
        }
    }
}
private let host = SUHost(bundle: Bundle.main)

func updateApplication(sharedContext _: SharedAccountContext) {
    switch stateValue.with({ $0.loadingState }) {
    case .readyToInstall:
        driver?.install(withToolAndRelaunch: true)
    case .hasUpdate:
        driver?.downloadUpdate()
    case .installing:
        break
    default:
        resetUpdater(manual: true, download: true)
    }
}


struct AppUpdateState : Equatable {
    let items: [SUAppcastItem]
    let loadingState: AppUpdateLoadingState
    
    fileprivate init(items: [SUAppcastItem], loadingState: AppUpdateLoadingState) {
        self.items = items
        self.loadingState = loadingState
        
    }
    func withUpdatedItems(_ items: [SUAppcastItem]) -> AppUpdateState {
        return AppUpdateState(items: items, loadingState: self.loadingState)
    }
    func withUpdatedLoadingState(_ loadingState: AppUpdateLoadingState) -> AppUpdateState {
        return AppUpdateState(items: self.items, loadingState: loadingState)
    }
}

extension String{
    var html2Attributed: NSAttributedString? {
        do {
            guard let data = data(using: String.Encoding.utf8) else {
                return nil
            }
            return try NSAttributedString(data: data,
                                          options: [.documentType: NSAttributedString.DocumentType.html,
                                                    .characterEncoding: String.Encoding.utf8.rawValue],
                                          documentAttributes: nil)
        } catch {
            print("error: ", error)
            return nil
        }
    }
}

private let _id_initializing: InputDataIdentifier = InputDataIdentifier("_id_initializing")
private let _id_downloading: InputDataIdentifier = InputDataIdentifier("_id_downloading")
private let _id_download_update: InputDataIdentifier = InputDataIdentifier("_id_download_update")
private let _id_install_update: InputDataIdentifier = InputDataIdentifier("_id_install_update")
private let _id_check_for_updates: InputDataIdentifier = InputDataIdentifier("_id_check_for_updates")
private let _id_unarchiving: InputDataIdentifier = InputDataIdentifier("_id_unarchiving")

private func appUpdateEntries(state: AppUpdateState, settings: RegramUpdateSettings) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    
    var sectionId: Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    var currentItem: SUAppcastItem?
    
    switch state.loadingState {
    case let .failed(error):
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_check_for_updates, data: InputDataGeneralData(name: updateString("AppUpdate.Check"), color: theme.colors.accent, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(error.localizedDescription), data: InputDataGeneralTextData(color: theme.colors.redUI, detectBold: false, viewType: .textBottomItem)))
        index += 1
        
    case let .hasUpdate(item):
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_download_update, data: InputDataGeneralData(name: strings().appUpdateDownloadUpdate, color: theme.colors.accent, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
        
        currentItem = item
    case .nonInited:
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_check_for_updates, data: .init(name: updateString("AppUpdate.Check"), color: theme.colors.accent, type: .none, viewType: .singleItem)))
        index += 1
    case .initializing:
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_initializing, data: InputDataGeneralData(name: updateString("AppUpdate.Checking"), color: theme.colors.grayText, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
    case let .loading(item, current, total):
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_downloading, data: InputDataGeneralData(name: "\(updateString("AppUpdate.Downloading"))  \(String.prettySized(with: current, forceDecimal: true) + " / " + String.prettySized(with: total))", color: theme.colors.grayText, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
        
        currentItem = item
    case .uptodate:
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_check_for_updates, data: InputDataGeneralData(name: updateString("AppUpdate.Check"), color: theme.colors.accent, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(updateString("AppUpdate.UpToDate")), data: InputDataGeneralTextData(detectBold: false, viewType: .textBottomItem)))
        index += 1
    case let .unarchiving(item):
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_unarchiving, data: InputDataGeneralData(name: updateString("AppUpdate.PreparingInstall"), color: theme.colors.grayText, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
        
        currentItem = item
    case let .readyToInstall(item):
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_install_update, data: InputDataGeneralData(name: updateString("AppUpdate.Install"), color: theme.colors.accent, icon: nil, type: .none, viewType: .singleItem, action: nil)))
        index += 1
        
        currentItem = item
    case .installing:
        break
    }
    
    
    if let item = currentItem {
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(updateString("AppUpdate.Available")), data: InputDataGeneralTextData(detectBold: false, viewType: .textTopItem)))
        index += 1
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    
        let text = "**" + item.versionTitle + "**" + "\n" + item.updateText
        entries.append(InputDataEntry.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier(item.fileURL.path), equatable: nil, comparable: nil, item: { initialSize, stableId in
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, textColor: theme.colors.listGrayText, fontSize: 13, isTextSelectable: true, viewType: .textTopItem)
        }))
        index += 1
    }
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    let preferences: [(String, String, Bool, () -> Void)] = [
        ("automaticCheck", "AppUpdate.AutomaticCheck", settings.automaticCheck, { changeUpdateSettings { $0.automaticCheck.toggle() } }),
        ("automaticDownload", "AppUpdate.AutomaticDownload", settings.automaticDownload, { changeUpdateSettings { $0.automaticDownload.toggle() } }),
        ("installOnQuit", "AppUpdate.InstallOnQuit", settings.installOnQuit, { changeUpdateSettings { $0.installOnQuit.toggle() } })
    ]
    for (position, preference) in preferences.enumerated() {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: InputDataIdentifier("updates." + preference.0), data: .init(name: updateString(preference.1), color: theme.colors.text, type: .switchable(preference.2), viewType: bestGeneralViewType(preferences, for: position), action: preference.3)))
        index += 1
    }
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(updateString("AppUpdate.MacAutomaticNotice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + ") · " + RegramUpdateArchitecture.current.rawValue
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: InputDataIdentifier("updates.version"), data: .init(name: updateString("AppUpdate.CurrentVersion"), color: theme.colors.text, type: .context(version), viewType: .firstItem)))
    index += 1
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: InputDataIdentifier("updates.github"), data: .init(name: updateString("AppUpdate.OpenGitHub"), color: theme.colors.text, type: .next, viewType: .lastItem, action: { NSWorkspace.shared.open(URL(string: "https://github.com/RegramDev/Regram-macos/releases")!) })))
    return entries
}



func AppUpdateViewController() -> InputDataController {
    
    let signal: Signal<InputDataSignalValue, NoError> = combineLatest(statePromise.get(), updaterSettings.get(), appearanceSignal) |> deliverOnResourceQueue |> map { value, settings, _ in
        return appUpdateEntries(state: value, settings: settings)
    } |> map { InputDataSignalValue(entries: $0) }
    

    return InputDataController(dataSignal: signal, title: updateString("AppUpdate.Title"), validateData: { data in
        
        if let _ = data[_id_download_update] {
            driver?.downloadUpdate()
        }
        if let _ = data[_id_check_for_updates] {
            regramCheckForUpdates()
        }
        if let _ = data[_id_install_update] {
            driver?.install(withToolAndRelaunch: true)
        }
        
        return .none
    }, afterDisappear: {

    }, hasDone: false, identifier: "app_update")
    
    
}

private func updateArchiveMatchesSHA256(at path: String, expectedSHA256: String, expectedSize: UInt64) -> Bool {
    guard let stream = InputStream(fileAtPath: path) else { return false }
    stream.open()
    defer { stream.close() }
    var hasher = SHA256()
    var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
    var size: UInt64 = 0
    while true {
        let length = stream.read(&buffer, maxLength: buffer.count)
        if length < 0 { return false }
        if length == 0 { break }
        size += UInt64(length)
        if size > expectedSize { return false }
        hasher.update(data: Data(buffer.prefix(length)))
    }
    return size == expectedSize && hasher.finalize().map { String(format: "%02x", $0) }.joined() == expectedSHA256
}

private class ExternalUpdateDriver: SUBasicUpdateDriver {
    private var releaseTask: URLSessionDataTask?
    private var expectedSHA256: String?
    private var downloadStarted = false
    private var verificationStarted = false
    private var archiveVerified = false
    private var archivePrepared = false
    private var installationStarted = false
    private var checkInProgress = false
    fileprivate var checkWasManual = false
    fileprivate var requestedDownload = false
    fileprivate var stagedOver: SUAppcastItem?

    deinit { releaseTask?.cancel() }

    fileprivate var isCheckingAutomatically: Bool {
        return checkInProgress && !checkWasManual
    }

    fileprivate var isCurrentDriver: Bool {
        return currentDriver.with { $0 } == ObjectIdentifier(self)
    }

    private var acceptsCallbacks: Bool {
        return !finished && (isCurrentDriver || stagedDriver === self)
    }

    private func onMain(_ action: @escaping (ExternalUpdateDriver) -> Void) {
        if Thread.isMainThread {
            action(self)
        } else {
            DispatchQueue.main.async { action(self) }
        }
    }

    override func isItemNewer(_ item: SUAppcastItem!) -> Bool {
        guard acceptsCallbacks, super.isItemNewer(item) else { return false }
        if let stagedOver {
            return SUStandardVersionComparator().compareVersion(stagedOver.versionString, toVersion: item.versionString) == .orderedAscending
        }
        return true
    }

    override func didFindValidUpdate() {
        guard acceptsCallbacks else { return }
        checkInProgress = false
        if requestedDownload || RegramUpdateSettings().automaticDownload {
            super.didFindValidUpdate()
        } else if stagedDriver === self {
            promoteStagedUpdate(self, prepared: false)
        } else {
            updateSharedState { $0.withUpdatedLoadingState(.hasUpdate(self.updateItem)) }
        }
    }

    fileprivate func updateSharedState(_ change: (AppUpdateState) -> AppUpdateState) {
        if isCurrentDriver && !finished { updateState(change) }
    }

    override func extractUpdate() {
        guard acceptsCallbacks, !verificationStarted else { return }
        guard let expectedSHA256, let path = downloadPath, let item = updateItem else {
            abortUpdateWithError(updateError(code: 2, key: "AppUpdate.InvalidRelease"))
            return
        }
        verificationStarted = true
        updateSharedState { $0.withUpdatedLoadingState(.unarchiving(item)) }
        resourcesQueue.async { [weak self] in
            let matches = updateArchiveMatchesSHA256(at: path, expectedSHA256: expectedSHA256, expectedSize: item.contentLength)
            DispatchQueue.main.async {
                guard let self, self.acceptsCallbacks else { return }
                if matches {
                    self.archiveVerified = true
                    self.extractVerifiedUpdate()
                } else {
                    self.abortUpdateWithError(updateError(code: 3, key: "AppUpdate.HashMismatch"))
                }
            }
        }
    }

    private func extractVerifiedUpdate() {
        super.extractUpdate()
    }

    override func install(withToolAndRelaunch relaunch: Bool, displayingUserInterface showUI: Bool) {
        guard Thread.isMainThread, acceptsCallbacks, isCurrentDriver, archivePrepared, !installationStarted else { return }
        installationStarted = true
        cancelStagedUpdate()
        updateSharedState { $0.withUpdatedLoadingState(.installing) }
        super.install(withToolAndRelaunch: relaunch, displayingUserInterface: showUI)
    }

    fileprivate func installWhenQuitting() {
        install(withToolAndRelaunch: false, displayingUserInterface: false)
    }

    override func appcastDidFinishLoading(_ appcast: SUAppcast!) {
        guard acceptsCallbacks else { return }
        updateSharedState { $0.withUpdatedItems(appcast.items?.compactMap { $0 as? SUAppcastItem } ?? []) }
        super.appcastDidFinishLoading(appcast)
    }

    override func didNotFindUpdate() {
        guard acceptsCallbacks else { return }
        checkInProgress = false
        let wasCurrent = isCurrentDriver
        if stagedDriver === self { dropStagedUpdate(self) }
        abortUpdate()
        if wasCurrent { updateState { _ in AppUpdateState(items: [], loadingState: .uptodate) } }
    }

    override func checkForUpdates(at url: URL!, host updateHost: SUHost!, domain: String!) {
        self.host = updateHost
        guard acceptsCallbacks else { return }
        guard !updateHost.isRunningOnReadOnlyVolume else {
            abortUpdateWithError(updateError(code: 4, key: "AppUpdate.MacReadOnly"))
            return
        }
        checkInProgress = true
        updateSharedState { $0.withUpdatedLoadingState(.initializing) }
        var request = URLRequest(url: updateFeedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Regram-macOS", forHTTPHeaderField: "User-Agent")
        releaseTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.acceptsCallbacks else { return }
                self.releaseTask = nil
                let status = (response as? HTTPURLResponse)?.statusCode
                guard error == nil, status == 200, let data else {
                    self.abortUpdateWithError(error ?? updateError(code: status ?? 0, key: status == 404 ? "AppUpdate.InvalidRelease" : "AppUpdate.NetworkError"))
                    return
                }
                do {
                    let build = Int64(updateHost.bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
                    guard let release = try RegramUpdatePolicy.release(from: data, currentBuild: build, architecture: .current) else {
                        self.didNotFindUpdate()
                        return
                    }
                    self.expectedSHA256 = release.sha256
                    let appcast = SUAppcast()
                    appcast.parseAppcastItems(fromXMLData: release.appcastData, error: nil)
                    guard (appcast.items as? [SUAppcastItem])?.count == 1 else { throw RegramUpdatePolicy.ValidationError.invalidRelease }
                    self.appcastDidFinishLoading(appcast)
                } catch {
                    self.abortUpdateWithError(updateError(code: 1, key: "AppUpdate.InvalidRelease"))
                }
            }
        }
        releaseTask?.resume()
    }

    override func downloadUpdate() {
        guard acceptsCallbacks, !downloadStarted, let item = updateItem else { return }
        downloadStarted = true
        updateSharedState { $0.withUpdatedLoadingState(.loading(item: item, current: 0, total: Int(item.contentLength))) }
        if stagedDriver === self {
            download = SPUDownloaderSession(delegate: self)
            download?.startPersistentDownload(with: SPUURLRequest(request: URLRequest(url: item.fileURL)), bundleIdentifier: host.bundle.bundleIdentifier!, desiredFilename: "Regram \(item.versionString ?? "")")
        } else {
            super.downloadUpdate()
        }
    }

    override func downloaderDidSetDestinationName(_ destinationName: String!, temporaryDirectory: String!) {
        onMain { current in
            current.acceptDownloadDestination(destinationName, temporaryDirectory: temporaryDirectory)
            if !current.acceptsCallbacks { current.cleanUpDownload() }
        }
    }

    private func acceptDownloadDestination(_ destinationName: String!, temporaryDirectory: String!) {
        super.downloaderDidSetDestinationName(destinationName, temporaryDirectory: temporaryDirectory)
    }

    override func downloaderDidFinish(withTemporaryDownloadData downloadData: SPUDownloadData!) {
        onMain { current in
            guard current.acceptsCallbacks else { return }
            current.extractUpdate()
        }
    }

    override func unarchiverDidFinish(_ unarchiver: Any!) {
        onMain { current in
            guard current.acceptsCallbacks, current.archiveVerified, !current.archivePrepared, let item = current.updateItem else { return }
            current.archivePrepared = true
            if stagedDriver === current {
                promoteStagedUpdate(current, prepared: true)
            } else {
                current.updateSharedState { $0.withUpdatedLoadingState(.readyToInstall(item)) }
            }
        }
    }

    override func unarchiver(_ unarchiver: Any!, extractedProgress progress: Double) {}

    override func downloaderDidReceiveData(ofLength length: UInt64) {
        onMain { current in
            guard current.acceptsCallbacks else { return }
            current.updateSharedState { state in
                if case let .loading(item, received, total) = state.loadingState {
                    return state.withUpdatedLoadingState(.loading(item: item, current: received + Int(clamping: length), total: total))
                }
                return state
            }
        }
    }

    override func downloaderDidReceiveExpectedContentLength(_ expectedContentLength: Int64) {
        onMain { current in
            guard current.acceptsCallbacks, let item = current.updateItem else { return }
            current.updateSharedState { state in
                guard case .loading = state.loadingState else { return state }
                return state.withUpdatedLoadingState(.loading(item: item, current: 0, total: expectedContentLength > 0 ? Int(expectedContentLength) : Int(item.contentLength)))
            }
        }
    }

    override func downloaderDidFailWithError(_ error: Error!) {
        abortUpdateWithError(error ?? updateError(code: 5, key: "AppUpdate.NetworkError"))
    }

    override func abortUpdate() {
        onMain { current in
            guard !current.finished else { return }
            current.releaseTask?.cancel()
            current.releaseTask = nil
            current.checkInProgress = false
            current.download?.cancel()
            current.finishAbortingUpdate()
        }
    }

    private func finishAbortingUpdate() {
        super.abortUpdate()
    }

    override func abortUpdateWithError(_ error: Error!) {
        onMain { current in
            guard current.acceptsCallbacks else { return }
            let wasCurrent = current.isCurrentDriver
            current.finishAbortingUpdate(with: error)
            if stagedDriver === current { dropStagedUpdate(current) }
            if wasCurrent {
                updateState { $0.withUpdatedLoadingState(.failed(error as NSError? ?? updateError(code: 0, key: "AppUpdate.NetworkError"))) }
            }
        }
    }

    private func finishAbortingUpdate(with error: Error!) {
        super.abortUpdateWithError(error)
    }
}

private func updateError(code: Int, key: String) -> NSError {
    return NSError(domain: "Regram.Update", code: code, userInfo: [NSLocalizedDescriptionKey: updateString(key)])
}

private let disposable = MetaDisposable()

func crashRecoveryUpdater() -> CrashRecoveryUpdater {
    let state: Signal<CrashRecoveryUpdateState, NoError> = appUpdateStateSignal |> map { state in
        switch state.loadingState {
        case .nonInited, .initializing:
            return .checking
        case let .loading(item, current, total):
            return .downloading(version: item.displayVersionString ?? "", current: current, total: total)
        case let .hasUpdate(item):
            return .downloading(version: item.displayVersionString ?? "", current: 0, total: Int(item.contentLength))
        case let .unarchiving(item):
            return .preparing(version: item.displayVersionString ?? "")
        case let .readyToInstall(item):
            return .readyToInstall(version: item.displayVersionString ?? "")
        case .installing:
            return .installing
        case .uptodate:
            return .upToDate
        case .failed:
            return .failed
        }
    }
    return CrashRecoveryUpdater(state: state, check: {
        regramCheckForUpdates(download: true)
    }, install: {
        if case .readyToInstall = stateValue.with({ $0.loadingState }) {
            driver?.install(withToolAndRelaunch: true)
        }
    })
}

func updateAppIfNeeded() {
    guard RegramUpdateSettings().installOnQuit else { return }
    guard Bundle.main.object(forInfoDictionaryKey: "RegramUpdatesDisabled") as? Bool != true else { return }
    let state = stateValue.with {$0.loadingState}
    
    switch state {
    case .readyToInstall:
        driver?.installWhenQuitting()
    default:
        break
    }
}


private var updateFeedURL: URL {
    URL(string: "https://api.github.com/repos/RegramDev/Regram-macos/releases/latest")!
}

private func makeUpdateDriver() -> ExternalUpdateDriver {
    ExternalUpdateDriver(updater: updater)
}

private var stagedDriver: ExternalUpdateDriver?
private var stagedStartedAt: CFAbsoluteTime = 0
private let stagedUpdateTimeout: CFAbsoluteTime = 60 * 60

private func stageNewerUpdate(manual: Bool, download: Bool) {
    guard case let .readyToInstall(item) = stateValue.with({ $0.loadingState }) else {
        return
    }
    if stagedDriver != nil {
        if CFAbsoluteTimeGetCurrent() - stagedStartedAt < stagedUpdateTimeout {
            return
        }
        cancelStagedUpdate()
    }
    if let downloadPath = driver?.downloadPath {
        let downloadDirectory = ((downloadPath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: downloadDirectory)
    }
    let staged = makeUpdateDriver()
    staged.checkWasManual = manual
    staged.requestedDownload = download
    staged.stagedOver = item
    stagedDriver = staged
    stagedStartedAt = CFAbsoluteTimeGetCurrent()
    staged.checkForUpdates(at: updateFeedURL, host: host, domain: nil)
}

private func promoteStagedUpdate(_ staged: ExternalUpdateDriver, prepared: Bool) {
    guard stagedDriver === staged, case .readyToInstall = stateValue.with({ $0.loadingState }) else {
        if stagedDriver === staged {
            stagedDriver = nil
        }
        staged.abortUpdate()
        return
    }
    stagedDriver = nil
    staged.stagedOver = nil
    driver = staged
    updateState { _ in
        AppUpdateState(items: [staged.updateItem], loadingState: prepared ? .readyToInstall(staged.updateItem) : .hasUpdate(staged.updateItem))
    }
}

private func dropStagedUpdate(_ staged: ExternalUpdateDriver) {
    guard stagedDriver === staged else {
        return
    }
    stagedDriver = nil
    staged.abortUpdate()
}

private func cancelStagedUpdate() {
    guard let staged = stagedDriver else {
        return
    }
    stagedDriver = nil
    staged.abortUpdate()
}

private func resetUpdater(manual: Bool = false, download: Bool = false) {
    guard Bundle.main.object(forInfoDictionaryKey: "RegramUpdatesDisabled") as? Bool != true else { return }
    let check: (Bool, Bool) -> Void = { manual, download in
        switch stateValue.with({ $0.loadingState }) {
        case .readyToInstall:
            stageNewerUpdate(manual: manual, download: download)
        case .hasUpdate where download:
            driver?.downloadUpdate()
        case .initializing:
            if manual, let driver {
                driver.checkWasManual = true
                driver.requestedDownload = driver.requestedDownload || download
            }
        case .installing, .unarchiving, .loading:
            break
        default:
            let current = makeUpdateDriver()
            current.checkWasManual = manual
            current.requestedDownload = download
            driver = current
            current.checkForUpdates(at: updateFeedURL, host: host, domain: nil)
        }
    }
    disposable.set(nil)
    if RegramUpdateSettings().automaticCheck {
        let signal: Signal<Never, NoError> = Signal { subscriber in
            check(false, false)
            subscriber.putCompletion()
            return EmptyDisposable
        } |> delay(20 * 60, queue: .mainQueue()) |> restart
        disposable.set(signal.start())
    }
    if manual || RegramUpdateSettings().automaticCheck { check(manual, download) }
}

func regramCheckForUpdates(download: Bool = false) {
    resetUpdater(manual: true, download: download)
}

private var updaterStarted = false

func startRegramUpdater() {
    guard !updaterStarted else { return }
    updaterStarted = true
    resetUpdater()
}


#endif
