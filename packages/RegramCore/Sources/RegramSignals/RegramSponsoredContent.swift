import SwiftSignalKit

public func regramSponsoredContent<Value>(hidden: Signal<Bool, NoError>, empty: Value, source: @escaping () -> Signal<Value, NoError>) -> Signal<Value, NoError> {
    hidden
    |> distinctUntilChanged
    |> mapToSignal { hidden in
        hidden ? .single(empty) : source()
    }
}
