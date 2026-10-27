import Foundation
import SwiftSignalKit

let starts = Atomic<[Int]>(value: [])
let releases = Atomic<[Int]>(value: [])
struct ActiveCall { let id: Int }
struct CallDescription { let id: Int; init(_ call: ActiveCall) { id = call.id } }
struct FixtureContext { let account = 1; let engine = 2 }
final class PanelContext {
    let id: Int
    let pipe = ValuePipe<Int?>()
    init(_ id: Int) { self.id = id }
    var panelData: Signal<Int?, NoError> { .single(id) |> then(pipe.signal()) }
}
final class Proxy {
    let context: PanelContext
    init(_ context: PanelContext) { self.context = context }
    func keep() {}
    deinit { _ = releases.modify { $0 + [context.id] } }
}
final class Cache {
    final class Impl {
        var panels: [Int: PanelContext] = [:]
        func get(account: Int, engine: Int, peerId: Int, isChannel: Bool, call: CallDescription, isMuted: Bool, e2eContext: Int?) -> Proxy {
            precondition(Thread.isMainThread)
            _ = starts.modify { $0 + [call.id] }
            let panel = panels[call.id] ?? PanelContext(call.id)
            panels[call.id] = panel
            return Proxy(panel)
        }
    }
    let impl = QueueLocalObject<Impl>(queue: .mainQueue(), generate: { Impl() })
}
final class GroupCallScreenUIHooks {
    static let shared = GroupCallScreenUIHooks()
    let cache = Cache()
    func cachedGroupCallContexts(_ context: FixtureContext) -> Cache { cache }
}
func fallback(_ id: Int) -> Signal<Int?, NoError> {
    let context = FixtureContext()
    let peerId = 100
    let isChannel = false
    let activeCall = ActiveCall(id: id)
    __PRODUCTION_FALLBACK_SIGNAL__
}

let db = DispatchQueue(label: "fixture.database")
var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); checks += 1 }
func drainMain() {
    let done = Atomic(value: false)
    DispatchQueue.main.async { _ = done.swap(true) }
    let deadline = Date().addingTimeInterval(2)
    while !done.with({ $0 }), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    expect(done.with { $0 }, "main continuation drains")
}
func sendOnDatabase(_ pipe: ValuePipe<Int>, _ values: [Int]) {
    let returned = DispatchSemaphore(value: 0)
    db.async { for value in values { pipe.putNext(value) }; returned.signal() }
    expect(returned.wait(timeout: .now() + 2) == .success, "database publisher returns while main is not draining")
}
let pipe1 = ValuePipe<Int>()
let op1 = (pipe1.signal() |> mapToSignal { fallback($0) }).start()
sendOnDatabase(pipe1,[1])
expect(starts.with { $0.isEmpty }, "cached UI context not touched from database queue")
op1.dispose()
drainMain()
expect(starts.with { $0.isEmpty }, "cancel before main start prevents context creation")

let pipe2 = ValuePipe<Int>()
var values2: [Int?] = []
let op2 = (pipe2.signal() |> mapToSignal { fallback($0) }).start(next: { values2.append($0); expect(Thread.isMainThread, "cached panel emission remains on main") })
sendOnDatabase(pipe2,[2,3])
drainMain()
expect(starts.with { $0 == [3] } && values2 == [3], "replaced pending call never starts or emits")
op2.dispose()
expect(releases.with { $0 == [3] }, "started proxy is released on dispose")

let pipe3 = ValuePipe<Int>()
var values3: [Int?] = []
let op3 = (pipe3.signal() |> mapToSignal { fallback($0) }).start(next: { values3.append($0); expect(Thread.isMainThread, "delayed cached panel emission remains on main") })
sendOnDatabase(pipe3,[4])
drainMain()
let panel4 = GroupCallScreenUIHooks.shared.cache.impl.syncWith { $0.panels[4]! }
let delivered = DispatchSemaphore(value: 0)
db.async { panel4.pipe.putNext(40); delivered.signal() }
expect(delivered.wait(timeout: .now() + 2) == .success, "later panel publisher does not block on main")
op3.dispose()
drainMain()
expect(values3 == [4], "queued panel delivery after disposal is discarded")
expect(releases.with { $0.contains(4) }, "cancel releases proxy capture after queued event drains")

let pipe4 = ValuePipe<Int>()
let holder4 = MetaDisposable()
var values4: [Int?] = []
holder4.set((pipe4.signal() |> mapToSignal { fallback($0) }).start(next: { value in values4.append(value); holder4.dispose() }))
sendOnDatabase(pipe4,[5])
drainMain()
expect(values4 == [5] && releases.with { $0.contains(5) }, "reentrant cancellation during synchronous initial panel delivery retains no proxy")

let pipe5 = ValuePipe<Int>()
var inlineValue: Int?
let op5 = (pipe5.signal() |> mapToSignal { fallback($0) }).start(next: { inlineValue = $0 })
pipe5.putNext(6)
expect(inlineValue == 6, "already-main subscription keeps existing inline delivery")
op5.dispose()
print("\(checks)/\(checks) actual fallback signal + release SwiftSignalKit queue/cancellation checks passed")
