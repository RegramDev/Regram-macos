import Foundation

public struct CaptureDeviceCandidate: Equatable {
    public let uniqueID: String
    public let isAvailable: Bool
    public init(uniqueID: String, isAvailable: Bool) {
        self.uniqueID = uniqueID
        self.isAvailable = isAvailable
    }
}

public typealias DevicesUpdate = (camera: String?, input: String?, output: String?, sampleUpdateIndex: Int?)

public struct DevicesChangeTracker {
    private var camera: String?
    private var input: String?
    private var output: String?
    private var sampleIndex: Int?

    public init() {
    }

    public mutating func update(camera: String?, input: String?, output: String?, sampleIndex: Int) -> DevicesUpdate {
        let sampleChanged = self.sampleIndex != sampleIndex
        var result: DevicesUpdate = (camera: nil, input: nil, output: nil, sampleUpdateIndex: nil)
        if self.input != input || sampleChanged {
            result.input = input ?? ""
        }
        if self.camera != camera {
            result.camera = camera ?? ""
        }
        if self.output != output || sampleChanged {
            result.output = output ?? ""
        }
        if sampleChanged {
            result.sampleUpdateIndex = sampleIndex
        }
        self.camera = camera
        self.input = input
        self.output = output
        self.sampleIndex = sampleIndex
        return result
    }
}


public enum DeviceSelectionPolicy {
    public static func capture(selectedId: String?, candidates: [CaptureDeviceCandidate], defaultId: String?) -> String? {
        if let selectedId, candidates.contains(where: { $0.uniqueID == selectedId && $0.isAvailable }) { return selectedId }
        if let defaultId, candidates.contains(where: { $0.uniqueID == defaultId && $0.isAvailable }) { return defaultId }
        return candidates.first(where: { $0.isAvailable })?.uniqueID
    }

    public static func output(selectedId: String?, available: [String], defaultId: String?) -> String? {
        let available = available.filter { !$0.isEmpty }
        if let selectedId, available.contains(selectedId) { return selectedId }
        if let defaultId, available.contains(defaultId) { return defaultId }
        return available.first
    }
}
