import Foundation
import RegramCore
import SwiftSignalKit

private let suite = "RegramComposerBindingChecks." + UUID().uuidString
private let fixtureDefaults = UserDefaults(suiteName: suite)!
private let fixturePreferences = RegramPreferences(defaults: fixtureDefaults)

private struct CheckFailure: Error { let message: String }
private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    guard value() else { throw CheckFailure(message: message) }
}
private func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.025)) }

private struct FixturePeer { func toInt64() -> Int64 { 101 } }
private struct FixtureContext { let peerId = FixturePeer() }
private struct FixturePresentation {
    let effectiveInput: String
    let botMenu = 0
}
private final class FixtureInteraction {
    var presentation = FixturePresentation(effectiveInput: "https://x.com/user/status/12")
}

private final class ComposerHarness {
    let context = FixtureContext()
    let presentationDisposable = DisposableSet()
    let stage = ValuePromise(false, ignoreRepeated: true)
    var viewOnStage: Signal<Bool, NoError> { stage.get() }
    var visibleMessageWorkEnabled = false
    var regramComposerRefreshState = RegramComposerRefreshState()
    var contextQueryState: (String?, Disposable)?
    var urlPreviewQueryState: (String?, Disposable)?
    var urlPreviewDetectionToken = UUID()
    let updateUrlDisposable = MetaDisposable()
    let chatInteraction = FixtureInteraction()
    var contextReloads = 0
    var previewReloads = 0
    var contextCancellations = 0
    var previewCancellations = 0
    var detectionCancellations = 0
    var staleCallbacksApplied = 0
    var cacheWasNotCleared = false
    var contextDeliveries: [() -> Void] = []
    var previewDeliveries: [() -> Void] = []
    var detectionDeliveries: [() -> Void] = []

    func bind() {
        let context = self.context
        __BINDINGS__
    }

    __CANCEL__

    func notify(with value: Any, oldValue: Any, animated: Bool, force: Bool, composerRefresh: RegramComposerRefresh) {
        let value = value as! FixturePresentation
        let oldValue = oldValue as! FixturePresentation
        let input = value.effectiveInput
        let inputChanged = __INPUT_CHANGE__
        if __CONTEXT_GUARD__ {
            if composerRefresh.contains(.context), contextQueryState != nil { cacheWasNotCleared = true }
            contextQueryState?.1.dispose()
            contextReloads += 1
            let queryRequest = MetaDisposable()
            contextQueryState = (input, queryRequest)
            queryRequest.set(ActionDisposable { [weak self] in self?.contextCancellations += 1 })
            contextDeliveries.append { [weak self, weak queryRequest] in
                if let self, let queryRequest, __CONTEXT_OWNER__ { self.staleCallbacksApplied += 1 }
            }
        }
        if __PREVIEW_GUARD__ {
            if composerRefresh.contains(.preview), urlPreviewQueryState != nil { cacheWasNotCleared = true }
            urlPreviewQueryState?.1.dispose()
            previewReloads += 1
            let detectionToken = UUID()
            urlPreviewDetectionToken = detectionToken
            updateUrlDisposable.set(ActionDisposable { [weak self] in self?.detectionCancellations += 1 })
            let previewRequest = MetaDisposable()
            urlPreviewQueryState = (input, previewRequest)
            previewRequest.set(ActionDisposable { [weak self] in self?.previewCancellations += 1 })
            previewDeliveries.append { [weak self, weak previewRequest] in
                if let self, let previewRequest, __PREVIEW_OWNER__ { self.staleCallbacksApplied += 1 }
            }
            detectionDeliveries.append { [weak self] in
                if let self, __DETECTION_GUARD__ { self.staleCallbacksApplied += 1 }
            }
        }
    }

    func show() { visibleMessageWorkEnabled = true; stage.set(true); pump() }
    func hide() { visibleMessageWorkEnabled = false; stage.set(false); pump() }
    func startDraft() {
        notify(with: chatInteraction.presentation, oldValue: FixturePresentation(effectiveInput: ""), animated: false, force: false, composerRefresh: [])
    }
    func stop() { presentationDisposable.dispose(); cancelRegramComposerQueries([.context, .preview]) }
    deinit { stop() }
}

@main
struct ComposerBindingChecks {
    static func run() throws {
        defer { fixtureDefaults.removePersistentDomain(forName: suite) }
        var harness: ComposerHarness? = ComposerHarness()
        weak var owner = harness
        harness!.bind()
        harness!.show()
        harness!.startDraft()
        let draft = harness!.chatInteraction.presentation.effectiveInput
        let oldContext = harness!.contextQueryState!.1
        let oldPreview = harness!.urlPreviewQueryState!.1
        let oldContextCallback = harness!.contextDeliveries[0]
        let oldPreviewCallback = harness!.previewDeliveries[0]
        let oldDetectionCallback = harness!.detectionDeliveries[0]
        fixturePreferences.update(accountId: 101) { $0["disableLinkPreview"] = .bool(true) }
        pump()
        try check(harness!.previewReloads == 2 && harness!.previewCancellations == 1 && harness!.detectionCancellations == 1, "Changing preview settings did not cancel and refresh the same-text draft")
        try check(harness!.contextReloads == 1 && harness!.contextCancellations == 0, "Preview settings restarted an unrelated inline query")
        oldPreviewCallback()
        oldDetectionCallback()
        try check(harness!.staleCallbacksApplied == 0, "An obsolete preview callback restored stale output")
        fixturePreferences.update(accountId: 101) { $0["features.autoInlineBotEnabled"] = .bool(true) }
        pump()
        try check(harness!.contextReloads == 2 && harness!.contextCancellations == 1, "Inline setting did not refresh unchanged input")
        try check(harness!.previewReloads == 2, "Inline setting restarted an unrelated preview")
        oldContextCallback()
        try check(harness!.staleCallbacksApplied == 0, "An obsolete inline callback restored stale output")
        withExtendedLifetime((oldContext, oldPreview)) {}

        fixturePreferences.update(accountId: 101) { $0["transcriptionBackend"] = .string("apple"); $0["defaultOutgoingFormatting"] = .string("bold"); $0["outgoingPhotoQuality"] = .integer(72) }
        fixturePreferences.update(accountId: 202) { $0["disableLinkPreview"] = .bool(true) }
        pump()
        try check(harness!.contextReloads == 2 && harness!.previewReloads == 2, "Unrelated settings or another account refreshed the composer")
        harness!.hide()
        fixturePreferences.update(accountId: 101) { $0["features.autoInlineBotEnabled"] = .bool(false); $0["linkPreviewXHost"] = .string("hidden.example.test") }
        pump()
        try check(harness!.contextQueryState == nil && harness!.urlPreviewQueryState == nil, "Hidden setting changes retained old query ownership")
        try check(harness!.contextReloads == 2 && harness!.previewReloads == 2, "Hidden setting changes started new queries")
        harness!.show()
        try check(harness!.contextReloads == 3 && harness!.previewReloads == 3, "Returning to the composer did not apply deferred settings once")
        fixturePreferences.update(accountId: 101) { $0["linkPreviewXHost"] = .string("intermediate.example.test") }
        fixturePreferences.update(accountId: 101) { $0["linkPreviewXHost"] = .string("latest.example.test") }
        pump()
        try check(harness!.previewReloads == 4 && harness!.contextReloads == 3, "Rapid preview edits did not coalesce to the latest configuration")
        try check(!harness!.cacheWasNotCleared, "A same-URL cache key survived a preference refresh")
        try check(harness!.chatInteraction.presentation.effectiveInput == draft, "Setting refresh changed the draft")
        harness!.stop()
        fixturePreferences.update(accountId: 101) { $0["disableLinkPreview"] = .bool(false) }
        pump()
        try check(harness!.previewReloads == 4 && harness!.contextReloads == 3, "Disposed bindings still refreshed queries")
        harness = nil
        try check(owner == nil, "Composer binding retained its removed owner")
        let report: [String: Any] = ["sameDraftSettingsRefresh": true, "independentQueryCancellation": true, "hiddenWorkDeferred": true, "latestConfigurationCoalesced": true, "obsoleteCallbacksRejected": true, "draftPreserved": true, "ownerReleased": true, "chatMessagesSent": 0, "realAccountAccess": false, "networkRequests": 0]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }

    static func main() {
        do { try run() }
        catch {
            let message = (error as? CheckFailure)?.message ?? String(describing: error)
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
    }
}
