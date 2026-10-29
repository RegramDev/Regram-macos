import SwiftSignalKit

final class ChatHistoryRenderGate {
    private struct State {
        var active = true
        var version: UInt64 = 0
    }

    private let state = Atomic(value: State())

    func setActive(_ active: Bool) {
        _ = state.modify { current in
            var current = current
            if current.active != active {
                current.active = active
                current.version &+= 1
            }
            return current
        }
    }

    func capture() -> UInt64? {
        return state.with { $0.active ? $0.version : nil }
    }

    func isCurrent(_ version: UInt64?) -> Bool {
        return state.with { $0.active && version == $0.version }
    }
}

struct ChatHistoryRenderingUpdate<Value> {
    let value: Value
    let version: UInt64?
}

func chatHistoryRenderingUpdates<Value>(_ history: Signal<Value, NoError>, visibility: Signal<Bool, NoError>, gate: ChatHistoryRenderGate) -> Signal<ChatHistoryRenderingUpdate<Value>, NoError> {
    return combineLatest(history, visibility) |> map { value, _ in
        return ChatHistoryRenderingUpdate(value: value, version: gate.capture())
    } |> filter { $0.version != nil }
}
