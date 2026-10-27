import Foundation
import SwiftSignalKit

enum TextRecognizing {
    struct Result: Equatable { let id: Int }
    enum Error { case generic }
    static var requests: [Int: Subscriber<Result, Error>] = [:]
    static func recognize(_ image: Int, postbox: Int, stableId: Int) -> Signal<Result, Error> {
        Signal { subscriber in requests[image] = subscriber; return EmptyDisposable }
    }
}
struct FixtureImage: Equatable { let _cgImage: Int? }
struct FixtureImageContainer: Equatable {
    enum Value: Equatable { case image(FixtureImage?, Int), empty }
    let value: Value
}
final class FixtureItem {
    let image = ValuePromise(FixtureImageContainer(value: .image(FixtureImage(_cgImage: 1), 0)))
    let magnify = ValuePromise<CGFloat>(1)
    let appear = ValuePromise(true)
    var appearValue: Signal<Bool, NoError> { appear.get() }
}
final class Fixture {
    var sourceIsVisible = false
    var result: TextRecognizing.Result?
    var history: [Int?] = []
    let disposable = MetaDisposable()
    func applyResult(_ result: TextRecognizing.Result?) { self.result = result; history.append(result?.id) }
    func start(_ item: FixtureItem) {
        let postbox = 0
        let mediaId = 0
        let fullImageLoaded = Signal<Void, NoError>.single(())
        __OCR_PIPELINE__

    }
    deinit { disposable.dispose() }
}
let item = FixtureItem()
let fixture = Fixture()
fixture.start(item)
precondition(TextRecognizing.requests[1] != nil)
let old = TextRecognizing.requests[1]!
DispatchQueue.main.async { item.image.set(FixtureImageContainer(value: .image(FixtureImage(_cgImage: 2), 0))) }
let ready = DispatchSemaphore(value: 0)
DispatchQueue.global().async { old.putNext(.init(id: 1)); ready.signal() }
precondition(ready.wait(timeout: .now() + 2) == .success)
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
precondition(TextRecognizing.requests[2] != nil)
print("PRODUCTION OCR DELIVERY:","activeImage",2,"visible",fixture.sourceIsVisible,"appliedResult",fixture.result?.id as Any,"history",fixture.history)
if CommandLine.arguments.contains("--expect-stale") {
    precondition(fixture.result?.id == 1)
    print("Previous pipeline negative control reproduced stale OCR source1 on active source2")
} else {
    precondition(fixture.result == nil)
    TextRecognizing.requests[2]!.putNext(.init(id: 2))
    precondition(fixture.result?.id == 2)
    item.appear.set(false)
    old.putNext(.init(id: 1))
    precondition(!fixture.sourceIsVisible && fixture.result == nil)
    print("Production OCR pipeline passed queued old-source, active-source delivery and hidden-source checks")
}
