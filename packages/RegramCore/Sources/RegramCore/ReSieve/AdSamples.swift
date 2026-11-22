import CryptoKit
import Foundation

public enum RGAdLabel: String, Codable, CaseIterable {
    case normal, ad, uncertain
}

public struct RGAdSpan: Codable, Equatable {
    public let range: RGAdRange
    public let label: RGAdLabel
    public init(_ range: RGAdRange, _ label: RGAdLabel) {
        self.range = range
        self.label = label
    }
}

public struct RGAdDetection: Codable, Equatable {
    public let recordedAt: Double
    public let policyRevision: Int
    public let removedRanges: [RGAdRange]
    public let removedButtonIds: [String]
    public let hidMessage: Bool
}

public struct RGAdSample: Codable, Equatable {
    public let schemaVersion: Int
    public let offsetUnit: String
    public let id: String
    public let sourceGroup: String
    public let input: RGAdInput
    public let mediaKinds: [String]
    public var spans: [RGAdSpan]
    public var buttonLabels: [String: RGAdLabel]
    public var mediaLabel: RGAdLabel
    public var reviewedAt: Double?
    public var detection: RGAdDetection? = nil

    public var recordedAt: Double { reviewedAt ?? detection?.recordedAt ?? 0 }
    public var isTrainingReady: Bool { reviewedAt != nil && !hasUncertainty }

    public mutating func mark(_ range: NSRange, as label: RGAdLabel) throws {
        guard range.location >= 0, range.length > 0, range.location <= input.text.utf16.count,
            range.length <= input.text.utf16.count - range.location
        else { throw RGAdSampleError.invalid }
        let source = input.text as NSString
        let expanded = source.rangeOfComposedCharacterSequences(for: range)
        var selected = RGAdRange(expanded.location, NSMaxRange(expanded))
        var changed = true
        while changed {
            changed = false
            for entity in input.entities
            where [.link, .mention, .customEmoji].contains(entity.kind) && entity.range.intersects(selected)
                && !selected.contains(entity.range)
            {
                selected = RGAdRange(min(selected.lower, entity.range.lower), max(selected.upper, entity.range.upper))
                changed = true
            }
        }
        var result: [RGAdSpan] = []
        for span in spans {
            if !span.range.intersects(selected) {
                result.append(span)
                continue
            }
            if span.range.lower < selected.lower { result.append(RGAdSpan(RGAdRange(span.range.lower, selected.lower), span.label)) }
            if span.range.upper > selected.upper { result.append(RGAdSpan(RGAdRange(selected.upper, span.range.upper), span.label)) }
        }
        if label != .normal { result.append(RGAdSpan(selected, label)) }
        spans = []
        for span in result.sorted(by: { $0.range.lower < $1.range.lower }) {
            if let last = spans.last, last.label == span.label, last.range.upper == span.range.lower {
                spans[spans.count - 1] = RGAdSpan(RGAdRange(last.range.lower, span.range.upper), span.label)
            } else {
                spans.append(span)
            }
        }
    }

    public var previewText: String {
        (try? RGAdFilter.project(
            input, confirmedRanges: spans.filter { $0.label == .ad }.map(\.range),
            confirmedButtonIds: Set(buttonLabels.filter { $0.value == .ad }.keys), inferButtons: false
        ).text) ?? input.text
    }

    public var hasAds: Bool {
        spans.contains { $0.label == .ad } || buttonLabels.values.contains(.ad) || (!mediaKinds.isEmpty && mediaLabel == .ad)
    }
    public var hasUncertainty: Bool {
        spans.contains { $0.label == .uncertain } || buttonLabels.values.contains(.uncertain)
            || (!mediaKinds.isEmpty && mediaLabel == .uncertain)
    }

    public func validate() throws {
        let boundaries = rgAdBoundaries(input.text)
        let ids = input.buttons.flatMap { $0 }.map(\.id)
        guard schemaVersion == 1, offsetUnit == "utf16", id.count == 64, id.allSatisfy({ $0.isHexDigit }),
            sourceGroup.count == 64, input.peerId == nil, input.text.utf16.count <= 65_536,
            input.entities.count <= 2048, ids.count <= 128, Set(ids).count == ids.count,
            Set(buttonLabels.keys) == Set(ids), mediaKinds.count <= 32, spans.count <= 1024,
            input.entities.allSatisfy({ rgAdValid($0.range, boundaries: boundaries) }),
            input.buttons.flatMap({ $0 }).allSatisfy({ $0.title.utf16.count <= 1024 && ($0.target?.utf16.count ?? 0) <= 8192 })
        else { throw RGAdSampleError.invalid }
        var end = 0
        for span in spans {
            guard span.label != .normal, rgAdValid(span.range, boundaries: boundaries), span.range.lower >= end else {
                throw RGAdSampleError.invalid
            }
            end = span.range.upper
        }
        if let detection {
            guard detection.recordedAt.isFinite, detection.recordedAt > 0,
                detection.policyRevision > 0, detection.removedRanges.count <= 1024,
                detection.removedRanges.allSatisfy({ rgAdValid($0, boundaries: boundaries) }),
                Set(detection.removedButtonIds).isSubset(of: Set(ids))
            else { throw RGAdSampleError.invalid }
        }
        if let reviewedAt, !reviewedAt.isFinite || reviewedAt <= 0 { throw RGAdSampleError.invalid }
    }
}

public enum RGAdSampleError: Error, Equatable { case invalid, capacity, damaged, changed }

@available(macOS 10.15, *)
public final class RGAdSampleStore {
    public static let maximumSamples = 10_000
    public let directory: URL
    public private(set) var recordingFailed = false
    private var storedIds: Set<String>?
    private var reviewedIds: Set<String>?
    private var indexedDirectoryModified: Double?
    private var cachedSalt: String?
    public init(accountDirectory: URL) { directory = accountDirectory.appendingPathComponent("regram-ad-samples-v1", isDirectory: true) }

    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        #endif
    }

    public func salt() throws -> String {
        if let cachedSalt { return cachedSalt }
        try prepare()
        let path = directory.appendingPathComponent("source-salt")
        if FileManager.default.fileExists(atPath: path.path) {
            let value = try String(contentsOf: path, encoding: .utf8)
            guard UUID(uuidString: value) != nil else { throw RGAdSampleError.damaged }
            cachedSalt = value
            return value
        }
        let value = UUID().uuidString
        try Data(value.utf8).write(to: path, options: .atomic)
        cachedSalt = value
        return value
    }

    public static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    public static func sourceGroup(salt: String, peerId: Int64) -> String { digest(salt + ":source:" + String(peerId)) }

    public static func sampleId(input: RGAdInput, salt: String, messageKey: String, mediaIdentity: String) throws -> String {
        let sanitized = RGAdInput(
            text: input.text, entities: input.entities, buttons: input.buttons, hasMedia: input.hasMedia, previewTarget: input.previewTarget
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let content = try encoder.encode(sanitized)
        return digest(salt + ":message:" + messageKey + ":" + content.base64EncodedString() + ":" + mediaIdentity)
    }

    public func draft(input: RGAdInput, messageKey: String, mediaKinds: [String], mediaIdentity: String) throws -> RGAdSample {
        let salt = try self.salt()
        let id = try Self.sampleId(input: input, salt: salt, messageKey: messageKey, mediaIdentity: mediaIdentity)
        return try draft(input: input, mediaKinds: mediaKinds, salt: salt, id: id)
    }

    private func draft(input: RGAdInput, mediaKinds: [String], salt: String, id: String) throws -> RGAdSample {
        let source = Self.sourceGroup(salt: salt, peerId: input.peerId ?? 0)
        let sanitized = RGAdInput(
            text: input.text, entities: input.entities, buttons: input.buttons, hasMedia: input.hasMedia, previewTarget: input.previewTarget
        )
        let file = directory.appendingPathComponent(id + ".json")
        if FileManager.default.fileExists(atPath: file.path) { return try read(file) }
        let sample = RGAdSample(
            schemaVersion: 1, offsetUnit: "utf16", id: id, sourceGroup: source, input: sanitized, mediaKinds: mediaKinds,
            spans: [], buttonLabels: Dictionary(uniqueKeysWithValues: input.buttons.flatMap { $0 }.map { ($0.id, .uncertain) }),
            mediaLabel: .uncertain, reviewedAt: nil)
        try sample.validate()
        return sample
    }

    private func read(_ file: URL) throws -> RGAdSample {
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1_048_576 else { throw RGAdSampleError.damaged }
        let sample = try JSONDecoder().decode(RGAdSample.self, from: Data(contentsOf: file))
        try sample.validate()
        guard sample.reviewedAt != nil || sample.detection != nil,
            file.lastPathComponent == sample.id + ".json"
        else { throw RGAdSampleError.damaged }
        return sample
    }

    private struct ReviewIndex: Codable {
        let version: Int
        let modified: Double
        let ids: [String]
        let checksum: String
    }
    private var indexDirectory: URL { directory.appendingPathComponent("index", isDirectory: true) }
    private var indexFile: URL { indexDirectory.appendingPathComponent("reviewed-v1.json") }
    private func directoryModified() throws -> Double {
        guard let date = try FileManager.default.attributesOfItem(atPath: directory.path)[.modificationDate] as? Date else {
            throw RGAdSampleError.damaged
        }
        return date.timeIntervalSince1970
    }
    private func indexChecksum(_ modified: Double, _ ids: [String]) -> String {
        Self.digest("reviews-v1:\(modified):" + ids.joined(separator: ":"))
    }
    private func loadReviewIndex() -> [String]? {
        guard let size = try? indexFile.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
            let data = try? Data(contentsOf: indexFile), let index = try? JSONDecoder().decode(ReviewIndex.self, from: data),
            index.version == 1, index.modified == (try? directoryModified()), index.ids.count <= Self.maximumSamples,
            Set(index.ids).count == index.ids.count, index.ids.allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }),
            index.checksum == indexChecksum(index.modified, index.ids)
        else { return nil }
        return index.ids
    }
    private func saveReviewIndex() {
        guard let reviewedIds else { return }
        do {
            try FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
            let modified = try directoryModified()
            let ids = reviewedIds.sorted()
            indexedDirectoryModified = modified
            let index = ReviewIndex(version: 1, modified: modified, ids: ids, checksum: indexChecksum(modified, ids))
            try JSONEncoder().encode(index).write(to: indexFile, options: .atomic)
        } catch {
        }
    }
    private func sampleFiles() throws -> [URL] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]).filter {
            $0.pathExtension == "json"
        }
        guard files.count <= Self.maximumSamples else { throw RGAdSampleError.capacity }
        return files
    }
    private func loadStoredIds() throws {
        if let indexedDirectoryModified, indexedDirectoryModified != (try directoryModified()) {
            storedIds = nil
            reviewedIds = nil
            self.indexedDirectoryModified = nil
        }
        guard storedIds == nil else { return }
        let ids = try sampleFiles().map { $0.deletingPathExtension().lastPathComponent }
        guard ids.allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) else { throw RGAdSampleError.damaged }
        storedIds = Set(ids)
    }
    private func prepareOptionalIndexForMutation() {
        let modified = try? directoryModified()
        if reviewedIds == nil || indexedDirectoryModified != modified {
            storedIds = nil
            reviewedIds = loadReviewIndex().map { Set($0) }
            indexedDirectoryModified = modified
        }
    }

    public func load(reviewedOnly: Bool = false, peerId: Int64? = nil) throws -> [RGAdSample] {
        try prepare()
        let sourceGroup = try peerId.map { Self.sourceGroup(salt: try salt(), peerId: $0) }
        if reviewedOnly, sourceGroup == nil, let ids = loadReviewIndex() {
            let samples = try ids.map { try read(directory.appendingPathComponent($0 + ".json")) }
            if samples.allSatisfy({ $0.reviewedAt != nil }) {
                reviewedIds = Set(ids)
                indexedDirectoryModified = try directoryModified()
                return samples.sorted { $0.recordedAt > $1.recordedAt }
            }
        }
        let files = try sampleFiles()
        var samples: [RGAdSample] = []
        var ids = Set<String>()
        var reviews = Set<String>()
        for file in files {
            let sample = try autoreleasepool { try read(file) }
            ids.insert(sample.id)
            if sample.reviewedAt != nil { reviews.insert(sample.id) }
            if (!reviewedOnly || sample.reviewedAt != nil) && (sourceGroup == nil || sample.sourceGroup == sourceGroup) {
                samples.append(sample)
            }
        }
        storedIds = ids
        reviewedIds = reviews
        if files.isEmpty {
            indexedDirectoryModified = try directoryModified()
        } else {
            saveReviewIndex()
        }
        return samples.sorted { $0.recordedAt > $1.recordedAt }
    }

    public func save(_ value: RGAdSample) throws {
        try value.validate()
        let path = directory.appendingPathComponent(value.id + ".json")
        var sample = value
        if FileManager.default.fileExists(atPath: path.path) {
            let current = try read(path)
            guard current.reviewedAt == value.reviewedAt else { throw RGAdSampleError.changed }
            sample.detection = current.detection
        } else if value.reviewedAt != nil || value.detection != nil {
            throw RGAdSampleError.changed
        }
        sample.reviewedAt = Date().timeIntervalSince1970
        try write(sample)
    }

    public func recordDetection(
        input: RGAdInput, messageKey: String, mediaKinds: [String], mediaIdentity: String, projection: RGAdProjection
    ) throws {
        guard projection.disposition != .keep else { return }
        do {
            let salt = try salt()
            let id = try Self.sampleId(input: input, salt: salt, messageKey: messageKey, mediaIdentity: mediaIdentity)
            try loadStoredIds()
            if storedIds?.contains(id) == true { return }
            var sample = try draft(input: input, mediaKinds: mediaKinds, salt: salt, id: id)
            guard sample.reviewedAt == nil, sample.detection == nil else { return }
            sample.detection = RGAdDetection(
                recordedAt: Date().timeIntervalSince1970, policyRevision: RGAdPolicy.revision,
                removedRanges: projection.removedRanges, removedButtonIds: projection.removedButtonIds,
                hidMessage: projection.disposition == .hide)
            sample.spans = projection.removedRanges.map { RGAdSpan($0, .ad) }
            for id in projection.removedButtonIds { sample.buttonLabels[id] = .ad }
            if projection.disposition == .hide { sample.mediaLabel = .ad }
            try write(sample)
            recordingFailed = false
        } catch {
            recordingFailed = true
            throw error
        }
    }

    private func write(_ sample: RGAdSample) throws {
        try sample.validate()
        try prepare()
        try loadStoredIds()
        if reviewedIds == nil { _ = try load(reviewedOnly: true) }
        if storedIds?.contains(sample.id) != true, (storedIds?.count ?? 0) >= Self.maximumSamples { throw RGAdSampleError.capacity }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(sample)
        guard data.count <= 1_048_576 else { throw RGAdSampleError.capacity }
        try data.write(to: directory.appendingPathComponent(sample.id + ".json"), options: .atomic)
        storedIds?.insert(sample.id)
        if sample.reviewedAt != nil { reviewedIds?.insert(sample.id) } else { reviewedIds?.remove(sample.id) }
        saveReviewIndex()
    }

    public func remove(_ sample: RGAdSample) throws {
        try sample.validate()
        prepareOptionalIndexForMutation()
        try FileManager.default.removeItem(at: directory.appendingPathComponent(sample.id + ".json"))
        storedIds?.remove(sample.id)
        reviewedIds?.remove(sample.id)
        saveReviewIndex()
    }

    public func export(trainingOnly: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = Data()
        for sample in try load() where !trainingOnly || sample.isTrainingReady {
            data.append(try encoder.encode(sample))
            data.append(0x0a)
            guard data.count <= 64 * 1024 * 1024 else { throw RGAdSampleError.capacity }
        }
        return data
    }
}
