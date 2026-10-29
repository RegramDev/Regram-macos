import SwiftSignalKit

func chatListVisibleStoryResources<Value>(visibility: Signal<Bool, NoError>, hidden: Signal<Bool, NoError>, empty: Value, load: @escaping () -> Signal<Value, NoError>) -> Signal<Value, NoError> {
    return combineLatest(visibility, hidden)
    |> distinctUntilChanged(isEqual: { $0.0 == $1.0 && $0.1 == $1.1 })
    |> deliverOnMainQueue
    |> mapToSignal { visible, hidden in
        if visible && !hidden {
            return load() |> deliverOnMainQueue
        }
        return .single(empty)
    }
}
