import CryptoKit
import Foundation

@available(macOS 10.15, *)
public final class RGAdSemanticCache {
    private struct Entry: Codable {
        let key: String
        let result: RGAdSemanticResult
        let createdAt: Double
        var cost: Int {
            384 + result.predictions.count * 128 + result.promotionalQuotes.count * 64
                + result.buttonIds.reduce(0) { $0 + 128 + $1.utf8.count * 2 }
        }
    }
    private struct Snapshot: Codable {
        let namespace: String
        let entries: [Entry]
    }
    private struct Envelope: Codable {
        let version: Int
        let payload: Data
        let checksum: String
    }
    private let namespace: String?
    private let salt: String
    private let file: URL
    private let now: () -> Double
    private var values = RGAdBoundedCache<String, Entry>(countLimit: 1024, costLimit: 512 * 1024)
    private var dirty = false
    private static let lifetime: Double = 7 * 24 * 3600
    public var count: Int { values.count }
    public var estimatedMemoryCost: Int { values.totalCost }

    public init(accountDirectory: URL, namespace: String?, salt: String, now: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.namespace = namespace
        self.salt = salt
        self.now = now
        file = accountDirectory.appendingPathComponent("regram-ad-cache-v1", isDirectory: true).appendingPathComponent("verdicts.json")
    }

    public static func bundledNamespace(resourceDirectory: URL? = nil) -> String? {
        func resource(_ name: String, _ ext: String) -> URL? {
            if let resourceDirectory {
                let url = resourceDirectory.appendingPathComponent(name).appendingPathExtension(ext)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
            #if SWIFT_PACKAGE
                if let url = Bundle.module.url(forResource: name, withExtension: ext) { return url }
                if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "ReSieveModel") { return url }
            #endif
            return Bundle.main.url(forResource: name, withExtension: ext)
        }
        guard let manifest = resource("RGAdModel", "json"), resource("RGAdVocabulary", "txt") != nil,
            resource("ReSieve", "mlmodelc") != nil || resource("ReSieve", "mlmodel") != nil,
            let data = try? Data(contentsOf: manifest), data.count <= 65_536,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["version"] as? Int == 1, let model = json["modelSHA256"] as? String, model.count == 64,
            let vocabulary = json["vocabularySHA256"] as? String, vocabulary.count == 64
        else { return nil }
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "development"
        return digest(Data("semantic-2:\(build):\(ProcessInfo.processInfo.operatingSystemVersionString):".utf8) + data)
    }

    public func key(for input: RGAdInput) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let encoded = try? encoder.encode(input) else { return nil }
        return Self.digest(Data((salt + ":semantic:").utf8) + encoded)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func current(_ entry: Entry) -> Bool {
        let time = now()
        return entry.createdAt.isFinite && entry.createdAt <= time + 300 && entry.createdAt >= time - Self.lifetime
    }
    private func valid(_ result: RGAdSemanticResult, for input: RGAdInput) -> Bool {
        guard result.completed, result.threshold.isFinite, (0.8...1).contains(result.threshold),
            result.predictions.count <= 1024, result.promotionalQuotes.count <= 128,
            result.buttonIds.count <= 128, result.buttonIds.allSatisfy({ $0.utf8.count <= 256 }),
            result.buttonIds.isSubset(of: Set(input.buttons.flatMap { $0 }.map(\.id))),
            result.predictions.allSatisfy({ $0.confidence.isFinite && (0...1).contains($0.confidence) })
        else { return false }
        if result.predictions.isEmpty && result.promotionalQuotes.isEmpty { return !result.entireMessage }
        let boundaries = rgAdBoundaries(input.text)
        return result.predictions.allSatisfy { rgAdValid($0.range, boundaries: boundaries) }
            && result.promotionalQuotes.allSatisfy { rgAdValid($0, boundaries: boundaries) }
    }
    public func result(for key: String?, input: RGAdInput) -> RGAdSemanticResult? {
        guard let key, let entry = values[key], current(entry), valid(entry.result, for: input) else { return nil }
        return entry.result
    }
    public func insert(_ result: RGAdSemanticResult, for key: String?, input: RGAdInput) {
        guard let key, key.count == 64, valid(result, for: input) else { return }
        if let previous = values[key], current(previous), previous.result == result { return }
        let entry = Entry(key: key, result: result, createdAt: now())
        values.insert(entry, for: key, cost: entry.cost)
        dirty = true
    }

    public func load() {
        guard let namespace else { return }
        do {
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 786_432 else { return }
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file))
            guard envelope.version == 1, envelope.payload.count <= 524_288,
                envelope.checksum == Self.digest(envelope.payload)
            else { return }
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: envelope.payload)
            guard snapshot.namespace == namespace, snapshot.entries.count <= 1024,
                Set(snapshot.entries.map(\.key)).count == snapshot.entries.count
            else { return }
            for entry in snapshot.entries
            where entry.key.count == 64 && entry.key.allSatisfy(\.isHexDigit) && entry.result.completed && current(entry) {
                values.insert(entry, for: entry.key, cost: entry.cost)
            }
        } catch {
        }
    }

    public func takeWriter() -> (() -> Void)? {
        guard dirty, let namespace else { return nil }
        dirty = false
        let snapshot = Snapshot(namespace: namespace, entries: values.orderedEntries.map { $0.1 }.filter(current))
        let file = self.file
        return {
            do {
                let payload = try JSONEncoder().encode(snapshot)
                guard payload.count <= 524_288 else { return }
                let envelope = Envelope(version: 1, payload: payload, checksum: Self.digest(payload))
                let data = try JSONEncoder().encode(envelope)
                guard data.count <= 786_432 else { return }
                let directory = file.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.createDirectory(
                        at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                    var url = directory
                    var attributes = URLResourceValues()
                    attributes.isExcludedFromBackup = true
                    try url.setResourceValues(attributes)
                    #if os(iOS)
                        try FileManager.default.setAttributes(
                            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
                    #endif
                }
                try data.write(to: file, options: .atomic)
            } catch {
            }
        }
    }

    public func removeAllFromMemory() {
        values.removeAll()
        dirty = false
    }
}
