import Foundation
import RegramCore
import SwiftSignalKit

public struct RegramTranscriptionTaskKey: Hashable {
    public let accountId: Int64
    public let messageId: RGBookmarkMessageId

    public init(accountId: Int64, messageId: RGBookmarkMessageId) {
        self.accountId = accountId
        self.messageId = messageId
    }
}

public enum RegramTranscriptionTaskState: String, Equatable {
    case running
    case completed
    case failed
    case cancelled
    case interrupted
}

public struct RegramTranscriptionTaskSnapshot: Equatable {
    public let key: RegramTranscriptionTaskKey
    public let threadId: Int64?
    public let state: RegramTranscriptionTaskState
    public let error: String?
    public let updatedAt: TimeInterval
}

public final class RegramTranscriptionTasks {
    private enum Outcome {
        case success
        case failure(RGTranscriptionError)
    }

    private final class Entry {
        let key: RegramTranscriptionTaskKey
        let token = RegramTaskToken()
        let revision: Int64
        let threadId: Int64?
        let operation: (@escaping () -> Bool) -> Signal<Void, RGTranscriptionError>
        let request = MetaDisposable()
        let outcome = Promise<Outcome>()
        var state: RegramTranscriptionTaskState = .running
        var error: String?
        var updatedAt = Date().timeIntervalSince1970

        init(key: RegramTranscriptionTaskKey, revision: Int64, threadId: Int64?, operation: @escaping (@escaping () -> Bool) -> Signal<Void, RGTranscriptionError>) {
            self.key = key
            self.revision = revision
            self.threadId = threadId
            self.operation = operation
        }

        var snapshot: RegramTranscriptionTaskSnapshot {
            RegramTranscriptionTaskSnapshot(key: key, threadId: threadId, state: state, error: error, updatedAt: updatedAt)
        }
    }

    public static let shared = RegramTranscriptionTasks()
    private let lock = NSRecursiveLock()
    private var entries: [RegramTranscriptionTaskKey: Entry] = [:]
    private let updates = ValuePromise<[RegramTranscriptionTaskSnapshot]>([], ignoreRepeated: true)
    private var suspended = false

    public init() {}

    public func signal(accountId: Int64) -> Signal<[RegramTranscriptionTaskSnapshot], NoError> {
        updates.get() |> map { $0.filter { $0.key.accountId == accountId } }
    }

    public func snapshot(_ key: RegramTranscriptionTaskKey) -> RegramTranscriptionTaskSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]?.snapshot
    }

    public func perform(key: RegramTranscriptionTaskKey, revision: Int64, threadId: Int64? = nil, operation: @escaping (@escaping () -> Bool) -> Signal<Void, RGTranscriptionError>) -> Signal<Void, RGTranscriptionError> {
        Signal { subscriber in
            let entry: Entry
            self.lock.lock()
            if let existing = self.entries[key], existing.state == .running, existing.revision == revision {
                entry = existing
            } else {
                if let previous = self.entries[key], previous.state == .running {
                    self.finish(previous, state: .cancelled, outcome: .failure(.cancelled))
                }
                entry = Entry(key: key, revision: revision, threadId: threadId, operation: operation)
                self.entries[key] = entry
                self.prune()
                if self.suspended {
                    self.finish(entry, state: .interrupted, outcome: .failure(.cancelled))
                } else {
                    self.publish()
                    self.start(entry)
                }
            }
            self.lock.unlock()
            return entry.outcome.get().start(next: { outcome in
                switch outcome {
                case .success: subscriber.putNext(()); subscriber.putCompletion()
                case let .failure(error): subscriber.putError(error)
                }
            })
        }
    }

    public func cancel(_ key: RegramTranscriptionTaskKey) {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key], entry.state == .running else { return }
        finish(entry, state: .cancelled, outcome: .failure(.cancelled))
    }

    public func retry(_ key: RegramTranscriptionTaskKey) {
        lock.lock()
        defer { lock.unlock() }
        guard !suspended, let previous = entries[key], previous.state != .running else { return }
        let entry = Entry(key: key, revision: previous.revision, threadId: previous.threadId, operation: previous.operation)
        entries[key] = entry
        publish()
        start(entry)
    }

    public func cancelAccount(_ accountId: Int64) {
        lock.lock()
        defer { lock.unlock() }
        let removed = entries.values.filter { $0.key.accountId == accountId }
        for entry in removed {
            if entry.state == .running { finish(entry, state: .cancelled, outcome: .failure(.cancelled)) }
            entries.removeValue(forKey: entry.key)
        }
        publish()
    }

    public func suspend() {
        lock.lock()
        defer { lock.unlock() }
        suspended = true
        for entry in Array(entries.values) where entry.state == .running {
            finish(entry, state: .interrupted, outcome: .failure(.cancelled))
        }
    }

    public func resume() {
        lock.lock()
        defer { lock.unlock() }
        suspended = false
        for key in entries.values.filter({ $0.state == .interrupted }).map(\.key) { retry(key) }
    }

    public func clearFinished(accountId: Int64) {
        lock.lock()
        defer { lock.unlock() }
        entries = entries.filter { $0.key.accountId != accountId || $0.value.state == .running || $0.value.state == .interrupted }
        publish()
    }

    private func start(_ entry: Entry) {
        let isCurrent = { [weak self, weak entry] () -> Bool in
            guard let self, let entry else { return false }
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.entries[entry.key] === entry && entry.state == .running && !self.suspended
        }
        entry.request.set(entry.operation(isCurrent).start(error: { [weak self, weak entry] error in
            guard let self, let entry else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard isCurrent() else { return }
            self.finish(entry, state: .failed, outcome: .failure(error))
        }, completed: { [weak self, weak entry] in
            guard let self, let entry else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard isCurrent() else { return }
            self.finish(entry, state: .completed, outcome: .success)
        }))
    }

    private func finish(_ entry: Entry, state: RegramTranscriptionTaskState, outcome: Outcome) {
        entry.state = state
        entry.updatedAt = Date().timeIntervalSince1970
        if case let .failure(error) = outcome { entry.error = error.localizedDescription }
        entry.request.dispose()
        entry.outcome.set(.single(outcome))
        publish()
    }

    private func prune() {
        let finished = entries.values.filter { $0.state != .running && $0.state != .interrupted }.sorted { $0.updatedAt < $1.updatedAt }
        for entry in finished.prefix(max(0, entries.count - 100)) { entries.removeValue(forKey: entry.key) }
    }

    private func publish() {
        updates.set(entries.values.map(\.snapshot).sorted { $0.updatedAt > $1.updatedAt })
    }
}
