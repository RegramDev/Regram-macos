import Foundation

public struct RegramDatacenterStatistics: Equatable {
    public var connectionMilliseconds: Double?
    public var connectionFailed = false
    public var connectionTimedOut = false
    public var samples: [Double] = []
    public var failures = 0
    public var timeouts = 0
    public var completed = false
    public init() {}
    public var average: Double? { samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count) }
    public var minimum: Double? { samples.min() }
    public var variation: Double? {
        guard let average else { return nil }
        return sqrt(samples.map { pow($0 - average, 2) }.reduce(0, +) / Double(samples.count))
    }
}
