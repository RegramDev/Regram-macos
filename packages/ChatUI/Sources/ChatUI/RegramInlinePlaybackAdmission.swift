import Cocoa
import RegramCore

private final class RegramInlinePlaybackEntry {
    weak var view: ChatInteractiveContentView?
    let accountId: Int64
    var candidate: RegramInlineVideoCandidate

    init(view: ChatInteractiveContentView, accountId: Int64, candidate: RegramInlineVideoCandidate) {
        self.view = view
        self.accountId = accountId
        self.candidate = candidate
    }
}

final class RegramInlinePlaybackAdmission {
    static let shared = RegramInlinePlaybackAdmission()
    private var entries: [Int64: RegramInlinePlaybackEntry] = [:]
    private var admitted = Set<Int64>()
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: RegramPreferences.didChange, object: nil, queue: .main) { [weak self] notification in
            guard let self, let accountId = notification.object as? Int64 else { return }
            for entry in self.entries.values where entry.accountId == accountId { entry.view?.updatePlayerIfNeeded() }
        }
    }

    func isAdmitted(view: ChatInteractiveContentView, accountId: Int64, candidate: RegramInlineVideoCandidate) -> Bool {
        if let entry = entries[candidate.id], entry.view === view { entry.candidate = candidate }
        else { entries[candidate.id] = RegramInlinePlaybackEntry(view: view, accountId: accountId, candidate: candidate) }
        reconcile()
        return admitted.contains(candidate.id)
    }

    func remove(id: Int64) {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.remove(id: id) }; return }
        guard entries.removeValue(forKey: id) != nil else { return }
        reconcile()
    }

    private func reconcile() {
        entries = entries.filter { $0.value.view != nil }
        let candidates = entries.values.compactMap { entry -> RegramInlineVideoCandidate? in
            guard let view = entry.view, view.window?.isKeyWindow == true, RegramPreferences.shared.settings(accountId: entry.accountId)["mediaLoadingExperiment"].bool else { return nil }
            let candidate = entry.candidate
            return RegramInlineVideoCandidate(id: candidate.id, stableId: candidate.stableId, eligible: candidate.eligible && !view.visibleRect.isEmpty, visibleFraction: candidate.visibleFraction, distanceFromCenter: candidate.distanceFromCenter, userInitiated: candidate.userInitiated, hasSound: candidate.hasSound, alreadyAdmitted: admitted.contains(candidate.id))
        }
        let selected = Set(RegramMediaLoadingPolicy.selectedInlineVideos(candidates, active: NSApp.isActive, thermalCritical: ProcessInfo.processInfo.thermalState == .critical))
        let changed = selected.symmetricDifference(admitted)
        admitted = selected
        for id in changed {
            guard let view = entries[id]?.view else { continue }
            DispatchQueue.main.async { [weak view] in view?.updatePlayerIfNeeded() }
        }
    }
}
