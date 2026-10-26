import Foundation

enum DeviceSelectionPolicyTests {
    private static func expectEqual<T: Equatable>(_ first: T, _ second: T) { precondition(first == second) }
    private static func expectNil<T>(_ value: T?) { precondition(value == nil) }
    static func testUnavailableDefaultAndReplug() {
        let connected = [CaptureDeviceCandidate(uniqueID: "preferred", isAvailable: true), CaptureDeviceCandidate(uniqueID: "fallback", isAvailable: true)]
        let unplugged = [CaptureDeviceCandidate(uniqueID: "preferred", isAvailable: false), CaptureDeviceCandidate(uniqueID: "fallback", isAvailable: true)]
        expectEqual(DeviceSelectionPolicy.capture(selectedId: "preferred", candidates: connected, defaultId: "fallback"), "preferred")
        expectEqual(DeviceSelectionPolicy.capture(selectedId: "preferred", candidates: unplugged, defaultId: "unavailable"), "fallback")
        expectEqual(DeviceSelectionPolicy.capture(selectedId: "preferred", candidates: connected, defaultId: "fallback"), "preferred")
        expectNil(DeviceSelectionPolicy.capture(selectedId: "preferred", candidates: [], defaultId: "stale"))
        expectEqual(DeviceSelectionPolicy.output(selectedId: "missing", available: ["", "speaker"], defaultId: "stale"), "speaker")
    }

    static func testDisappearanceClearsLiveRoutesAndReplugNotifies() {
        var tracker = DevicesChangeTracker()
        expectEqual(tracker.update(camera: "camera", input: "mic", output: "speaker", sampleIndex: 0).input, "mic")
        let unchanged = tracker.update(camera: "camera", input: "mic", output: "speaker", sampleIndex: 0)
        expectNil(unchanged.camera)
        expectNil(unchanged.input)
        expectNil(unchanged.output)
        let removed = tracker.update(camera: nil, input: nil, output: nil, sampleIndex: 0)
        expectEqual(removed.camera, "")
        expectEqual(removed.input, "")
        expectEqual(removed.output, "")
        let replugged = tracker.update(camera: "camera", input: "mic", output: "speaker", sampleIndex: 1)
        expectEqual(replugged.camera, "camera")
        expectEqual(replugged.input, "mic")
        expectEqual(replugged.output, "speaker")
    }
}

@main struct DeviceSelectionPolicyTestRunner {
    static func main() {
        DeviceSelectionPolicyTests.testUnavailableDefaultAndReplug()
        DeviceSelectionPolicyTests.testDisappearanceClearsLiveRoutesAndReplugNotifies()
        print("Device selection, unavailable defaults, unplug clearing and replug restoration passed.")
    }
}
