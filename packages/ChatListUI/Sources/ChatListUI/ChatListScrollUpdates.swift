import SwiftSignalKit

func chatListSettledScrollUpdates(_ events: Signal<Void, NoError>, visibility: Signal<Bool, NoError>, queue: Queue = .mainQueue()) -> Signal<Void, NoError> {
    return visibility
    |> distinctUntilChanged
    |> deliverOn(queue)
    |> mapToSignal { visible -> Signal<Void, NoError> in
        guard visible else { return .never() }
        return (.single(()) |> then(events |> deliverOn(queue)))
        |> mapToSignal { .single(()) |> delay(0.15, queue: queue) }
    }
}
