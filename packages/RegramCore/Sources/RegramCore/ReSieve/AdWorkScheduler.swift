import Foundation

public final class RGAdWorkRequest {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

public struct RGAdWorkConditions: Equatable {
    public var foreground: Bool
    public var lowPower: Bool
    public var thermal: Int
    public init(foreground: Bool = true, lowPower: Bool = false, thermal: Int = 0) {
        self.foreground = foreground
        self.lowPower = lowPower
        self.thermal = thermal
    }
    public var paused: Bool { !foreground || thermal >= 3 }
    public func recoveryDelay(workDuration: TimeInterval) -> TimeInterval {
        let multiplier = thermal >= 2 ? 7.0 : lowPower ? 3.0 : thermal == 1 ? 2.0 : 1.0
        return max(0.005, workDuration * multiplier)
    }
}

public final class RGAdWorkScheduler {
    private struct Job {
        let priority: Int
        let cancelled: () -> Bool
        let step: () -> Bool
        let onCancel: () -> Void
    }
    private let queue: DispatchQueue
    private var conditions = RGAdWorkConditions()
    private var jobs: [Job] = []
    private var scheduled: DispatchWorkItem?
    private var scheduledForInteractiveWork = false
    private var readyAt: TimeInterval = 0
    private var prioritySteps = 0
    public init(queue: DispatchQueue) { self.queue = queue }

    public func updateConditions(_ value: RGAdWorkConditions) {
        conditions = value
        pruneCancelled()
        if value.paused {
            scheduled?.cancel()
            scheduled = nil
        }
        schedule()
    }

    public func enqueue(priority: Int = 0, cancelled: @escaping () -> Bool, step: @escaping () -> Bool, onCancel: @escaping () -> Void) {
        pruneCancelled()
        jobs.append(Job(priority: priority, cancelled: cancelled, step: step, onCancel: onCancel))
        schedule()
    }

    public func discardCancelled() {
        pruneCancelled()
        if jobs.isEmpty {
            scheduled?.cancel()
            scheduled = nil
        } else {
            schedule()
        }
    }

    private func pruneCancelled() {
        let previous = jobs
        jobs.removeAll(keepingCapacity: true)
        for job in previous {
            if job.cancelled() { job.onCancel() } else { jobs.append(job) }
        }
    }

    private func schedule() {
        guard !conditions.paused, !jobs.isEmpty else { return }
        let interactive = !conditions.lowPower && conditions.thermal < 2 && jobs.contains { $0.priority > 0 }
        if let scheduled {
            guard scheduledForInteractiveWork != interactive else { return }
            scheduled.cancel()
        }
        let work = DispatchWorkItem(qos: interactive ? .userInitiated : .utility, flags: .enforceQoS) { [weak self] in self?.pump() }
        scheduled = work
        scheduledForInteractiveWork = interactive
        if interactive {
            queue.async(execute: work)
        } else {
            queue.asyncAfter(deadline: .now() + max(0, readyAt - ProcessInfo.processInfo.systemUptime), execute: work)
        }
    }

    private func pump() {
        scheduled = nil
        guard !conditions.paused else { return }
        let start = ProcessInfo.processInfo.systemUptime
        while !jobs.isEmpty {
            let highest = jobs.map(\.priority).max() ?? 0
            let preferred = jobs.firstIndex(where: { $0.priority == highest }) ?? 0
            let index = prioritySteps >= 3 ? 0 : preferred
            if index == 0 { prioritySteps = 0 } else { prioritySteps += 1 }
            let job = jobs.remove(at: index)
            if job.cancelled() { job.onCancel() } else if !autoreleasepool(invoking: job.step) { jobs.append(job) }
            if ProcessInfo.processInfo.systemUptime - start >= 0.012 { break }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        readyAt = ProcessInfo.processInfo.systemUptime + conditions.recoveryDelay(workDuration: elapsed)
        schedule()
    }
}
