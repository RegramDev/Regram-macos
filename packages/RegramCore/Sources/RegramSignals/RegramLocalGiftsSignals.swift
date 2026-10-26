import Foundation
import SwiftSignalKit
import RegramCore

public func regramLocalGiftsChanges(account: String, store: RGLocalGiftsStore = .shared, notifications: NotificationCenter = .default) -> Signal<RGLocalGiftsState, NoError> {
    Signal { subscriber in
        let observer = notifications.addObserver(forName: RGLocalGiftsStore.didChange, object: nil, queue: nil) { notification in
            guard notification.object as? String == account else { return }
            let committed = notification.userInfo?[RGLocalGiftsStore.committedStateKey] as? RGLocalGiftsState ?? store.state(account: account)
            Queue.mainQueue().async { subscriber.putNext(committed) }
        }
        subscriber.putNext(store.state(account: account))
        return ActionDisposable { notifications.removeObserver(observer) }
    } |> distinctUntilChanged |> deliverOnMainQueue
}
