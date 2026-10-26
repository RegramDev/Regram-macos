import Foundation
import RegramCore
import SwiftSignalKit

public func regramPreferenceChanges(accountId: Int64) -> Signal<RegramAccountSettings, NoError> {
    Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: RegramPreferences.didChange, object: nil, queue: nil) { notification in
            guard notification.object as? Int64 == accountId else { return }
            subscriber.putNext(RegramPreferences.shared.settings(accountId: accountId))
        }
        subscriber.putNext(RegramPreferences.shared.settings(accountId: accountId))
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
}

public func regramQuickTranslationChanges(accountId: Int64) -> Signal<Void, NoError> {
    Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: RegramQuickTranslationTasks.didChange, object: nil, queue: nil) { notification in
            if notification.object as? Int64 == accountId { subscriber.putNext(()) }
        }
        subscriber.putNext(())
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
}

public func regramRemarkChanges(accountId: Int64) -> Signal<Void, NoError> {
    Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: RGGroupRemarks.didChange, object: nil, queue: nil) { notification in
            guard (notification.object as? RGGroupRemarkChange)?.accountId == accountId else { return }
            subscriber.putNext(())
        }
        subscriber.putNext(())
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
}
