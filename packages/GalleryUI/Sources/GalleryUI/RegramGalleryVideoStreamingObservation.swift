import Foundation

final class RegramGalleryVideoStreamingObservation {
    private var observing = false
    private var active = false
    private var cancelObservation: (() -> Void)?
    private var releasePriority: (() -> Void)?

    deinit {
        cancelObservation?()
        releasePriority?()
    }

    func start(playerIsLoaded: Bool, isStreamable: Bool, observe: (@escaping (Bool) -> Void) -> (() -> Void), acquirePriority: @escaping () -> (() -> Void)) {
        guard playerIsLoaded, isStreamable, !observing else { return }
        observing = true
        cancelObservation = observe { [weak self] playing in
            guard let self, self.active != playing else { return }
            self.active = playing
            if playing {
                self.releasePriority = acquirePriority()
            } else {
                self.releasePriority?()
                self.releasePriority = nil
            }
        }
    }
}
