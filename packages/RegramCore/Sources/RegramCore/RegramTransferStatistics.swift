import Foundation

public final class RegramTransferStatistics {
    public struct Snapshot: Equatable {
        public let receivedBytes: Int64
        public let bytesPerSecond: Double
        public var roundedBytesPerSecond: Int64 {
            guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return 0 }
            return bytesPerSecond >= Double(Int64.max) ? Int64.max : Int64(bytesPerSecond)
        }
    }
    public static let rateInterval: TimeInterval = 3
    public static let shared = RegramTransferStatistics()
    private let lock = NSLock()
    private var samples: [(time: TimeInterval, bytes: Double)] = []
    private var sampleHead = 0
    private var windowBytes: Double = 0
    private var lastTime: TimeInterval = 0
    private var total: Int64 = 0
    public init() {}
    public func recordReceived(byteCount: Int, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard byteCount > 0, now.isFinite else { return }
        self.lock.lock(); defer { self.lock.unlock() }
        let now = max(now, self.lastTime)
        self.lastTime = now
        let bytes = Int64(byteCount)
        self.total = self.total > Int64.max - bytes ? Int64.max : self.total + bytes
        self.expireSamples(now: now)
        if self.samples.count > self.sampleHead, self.samples.last?.time == now {
            self.samples[self.samples.count - 1].bytes += Double(bytes)
        } else {
            self.samples.append((now, Double(bytes)))
        }
        self.windowBytes += Double(bytes)
    }
    public func snapshot(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Snapshot {
        self.lock.lock(); defer { self.lock.unlock() }
        guard now.isFinite else { return Snapshot(receivedBytes: self.total, bytesPerSecond: 0) }
        let now = max(now, self.lastTime)
        self.lastTime = now
        self.expireSamples(now: now)
        return Snapshot(receivedBytes: self.total, bytesPerSecond: self.windowBytes / Self.rateInterval)
    }
    private func expireSamples(now: TimeInterval) {
        while self.sampleHead < self.samples.count, now - self.samples[self.sampleHead].time >= Self.rateInterval {
            self.windowBytes -= self.samples[self.sampleHead].bytes
            self.sampleHead += 1
        }
        if self.sampleHead == self.samples.count {
            self.samples.removeAll(keepingCapacity: true)
            self.sampleHead = 0
            self.windowBytes = 0
        } else if self.sampleHead >= 512 && self.sampleHead >= self.samples.count / 2 {
            self.samples.removeFirst(self.sampleHead)
            self.sampleHead = 0
        }
        self.windowBytes = max(0, self.windowBytes)
    }
}
