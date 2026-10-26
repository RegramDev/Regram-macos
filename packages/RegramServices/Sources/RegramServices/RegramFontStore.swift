import Foundation
import AppKit
import CoreText
import CryptoKit
import SwiftSignalKit
import RegramCore

public struct RegramFontSelection: Equatable {
    public let fileId: String
    public let faceIndex: Int

    public init?(id: String) {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2, parts[0].count == 64, parts[0].allSatisfy({ $0.isHexDigit }) else { return nil }
        if parts.count == 2 {
            guard let index = Int(parts[1]), index > 0, String(index) == parts[1] else { return nil }
            faceIndex = index
        } else { faceIndex = 0 }
        fileId = String(parts[0]).lowercased()
    }

    public static func id(fileId: String, faceIndex: Int) -> String {
        faceIndex == 0 ? fileId : "\(fileId):\(faceIndex)"
    }
}

public struct RegramImportedFont: Codable, Equatable {
    public let id: String
    public var title: String
    public let latin: Bool
    public let chinese: Bool
    public var accountIds: [Int64]?
}

public enum RegramFontError: Error {
    case invalidFont
    case tooLarge
    case integrity
    case unavailable
    case cancelled
    case storage
}

struct RegramCloudFont: Decodable {
    let file: String
    let source: URL
    let sha256: String
    let bytes: Int
    let archive_member: String?
    let archive_sha256: String?
}

public struct RegramDownloadableFont: Decodable {
    public let id: String
    public let title: String
    public let group: String
    public let regular: String
    public let italic: String?
    public let selectionId: String
}

private struct RegramFontCatalog: Decodable {
    let files: [RegramCloudFont]
    let families: [RegramDownloadableFont]?
}

public final class RegramFontStore {
    public static let shared = RegramFontStore()
    public static let didChange = Notification.Name("Regram.FontStore.DidChange")
    public static let maximumImportBytes = 64 * 1024 * 1024
    public static let maximumDownloadBytes = 100 * 1024 * 1024
    private let root: URL
    private let lock = NSLock()
    private var values: [RegramImportedFont] = []
    private var registered: Set<URL> = []
    private var descriptors: [URL: [CTFontDescriptor]] = [:]
    private var version: Int64 = 0

    private static let catalog: RegramFontCatalog = {
        guard let url = Bundle.module.url(forResource: "RGFontCatalog", withExtension: "json"), let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(RegramFontCatalog.self, from: data) else { return RegramFontCatalog(files: [], families: nil) }
        return catalog
    }()

    public static var downloadableFonts: [RegramDownloadableFont] { catalog.families ?? [] }

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("app.regram.macos/fonts", isDirectory: true)
        if let data = try? Data(contentsOf: self.root.appendingPathComponent("imported.json")), data.count <= 1024 * 1024, let imported = try? JSONDecoder().decode([RegramImportedFont].self, from: data) {
            var seen = Set<String>()
            values = imported.filter { font in
                guard let selection = RegramFontSelection(id: font.id), seen.insert(font.id).inserted else { return false }
                return FileManager.default.fileExists(atPath: self.root.appendingPathComponent("Imported/\(selection.fileId).font").path)
            }
        }
    }

    deinit {
        for url in registered { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
    }

    public var imported: [RegramImportedFont] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    public var revision: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return version
    }

    public func importFonts(url: URL, accountId: Int64? = nil) throws -> [RegramImportedFont] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard attributes.isRegularFile == true, let size = attributes.fileSize, size > 0, size <= Self.maximumImportBytes else { throw RegramFontError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.isEmpty, data.count <= Self.maximumImportBytes else { throw RegramFontError.tooLarge }
        guard let fonts = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor], !fonts.isEmpty, fonts.count <= 256 else { throw RegramFontError.invalidFont }
        let hash = Self.hash(data)
        let imported = fonts.enumerated().compactMap { index, descriptor -> RegramImportedFont? in
            let font = CTFontCreateWithFontDescriptor(descriptor, 17, nil)
            let characters = CTFontCopyCharacterSet(font) as CharacterSet
            let latin = characters.contains("A".unicodeScalars.first!) && characters.contains("a".unicodeScalars.first!)
            let chinese = characters.contains("中".unicodeScalars.first!) || characters.contains("あ".unicodeScalars.first!) || characters.contains("한".unicodeScalars.first!)
            guard latin || chinese else { return nil }
            let title = (CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String) ?? url.deletingPathExtension().lastPathComponent
            return RegramImportedFont(id: RegramFontSelection.id(fileId: hash, faceIndex: index), title: String(title.prefix(80)), latin: latin, chinese: chinese, accountIds: accountId.map { [$0] })
        }
        guard !imported.isEmpty else { throw RegramFontError.invalidFont }
        lock.lock()
        do {
            try createRoot()
            let directory = root.appendingPathComponent("Imported", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(hash + ".font")
            if !FileManager.default.fileExists(atPath: destination.path) { try data.write(to: destination, options: .atomic) }
            let additions = imported.filter { font in !values.contains(where: { $0.id == font.id }) }
            var updated = values + additions
            if let accountId {
                for index in updated.indices where imported.contains(where: { $0.id == updated[index].id }) {
                    updated[index].accountIds = Array(Set((updated[index].accountIds ?? []) + [accountId])).sorted()
                }
            }
            try JSONEncoder().encode(updated).write(to: root.appendingPathComponent("imported.json"), options: .atomic)
            values = updated
            version &+= 1
            lock.unlock()
            publish()
            return imported
        } catch {
            lock.unlock()
            throw error
        }
    }

    public func retainSelections(settings: RegramAccountSettings, accountId: Int64) {
        let ids = Set([settings["fontImportedLatin"].string, settings["fontImportedChinese"].string].filter { !$0.isEmpty })
        guard !ids.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var updated = values
        var changed = false
        for index in updated.indices where ids.contains(updated[index].id) && !(updated[index].accountIds ?? []).contains(accountId) {
            updated[index].accountIds = Array(Set((updated[index].accountIds ?? []) + [accountId])).sorted()
            changed = true
        }
        guard changed, let data = try? JSONEncoder().encode(updated), (try? data.write(to: root.appendingPathComponent("imported.json"), options: .atomic)) != nil else { return }
        values = updated
    }

    public func removeAccount(accountId: Int64) throws {
        lock.lock()
        do {
            let old = values
            let updated = old.compactMap { font -> RegramImportedFont? in
                guard var accounts = font.accountIds, accounts.contains(accountId) else { return font }
                accounts.removeAll(where: { $0 == accountId })
                guard !accounts.isEmpty else { return nil }
                var font = font
                font.accountIds = accounts
                return font
            }
            guard updated != old else { lock.unlock(); return }
            try JSONEncoder().encode(updated).write(to: root.appendingPathComponent("imported.json"), options: .atomic)
            values = updated
            let retained = Set(updated.compactMap { RegramFontSelection(id: $0.id)?.fileId })
            let deleted = Set(old.filter { font in !updated.contains(where: { $0.id == font.id }) }.compactMap { RegramFontSelection(id: $0.id)?.fileId }).subtracting(retained)
            for fileId in deleted {
                let url = root.appendingPathComponent("Imported/\(fileId).font")
                unregister(url)
                try? FileManager.default.removeItem(at: url)
            }
            version &+= 1
            lock.unlock()
            publish()
        } catch { lock.unlock(); throw error }
    }

    public func rename(id: String, title: String) throws {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !title.isEmpty else { return }
        lock.lock()
        do {
            guard let index = values.firstIndex(where: { $0.id == id }) else { lock.unlock(); return }
            var updated = values
            updated[index].title = title
            try JSONEncoder().encode(updated).write(to: root.appendingPathComponent("imported.json"), options: .atomic)
            values = updated
            version &+= 1
            lock.unlock()
            publish()
        } catch { lock.unlock(); throw error }
    }

    public func remove(id: String) throws {
        guard let selection = RegramFontSelection(id: id) else { return }
        lock.lock()
        do {
            guard values.contains(where: { $0.id == id }) else { lock.unlock(); return }
            let updated = values.filter { $0.id != id }
            let indexURL = root.appendingPathComponent("imported.json")
            try JSONEncoder().encode(updated).write(to: indexURL, options: .atomic)
            if !updated.contains(where: { RegramFontSelection(id: $0.id)?.fileId == selection.fileId }) {
                let url = root.appendingPathComponent("Imported/\(selection.fileId).font")
                unregister(url)
                do { try FileManager.default.removeItem(at: url) }
                catch { try? JSONEncoder().encode(values).write(to: indexURL, options: .atomic); throw error }
            }
            values = updated
            version &+= 1
            lock.unlock()
            publish()
        } catch { lock.unlock(); throw error }
    }

    public func storageBytes(downloads: Bool) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let directory = root.appendingPathComponent(downloads ? "Cloud" : "Imported")
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        return files.compactMap { $0 as? URL }.reduce(Int64(0)) { sum, url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true else { return sum }
            return sum + Int64(values.fileSize ?? 0)
        }
    }

    public func clearDownloads() throws {
        lock.lock()
        do {
            let directory = root.appendingPathComponent("Cloud", isDirectory: true)
            for url in registered.filter({ $0.path.hasPrefix(directory.path + "/") }) { unregister(url) }
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            version &+= 1
            lock.unlock()
            publish()
        } catch { lock.unlock(); throw error }
    }

    public func isDownloaded(prefix: String) -> Bool {
        let files = Self.catalog.files.filter { $0.file.hasPrefix(prefix + "-") }
        guard !files.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        return files.allSatisfy { file in
            let url = root.appendingPathComponent("Cloud/\(prefix)/\(file.file)")
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == file.bytes
        }
    }

    func font(importedId: String, size: CGFloat, italic: Bool = false) -> NSFont? {
        guard let selection = RegramFontSelection(id: importedId) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let family = Self.downloadableFonts.first(where: { $0.selectionId == importedId }) {
            let filename = italic ? family.italic ?? family.regular : family.regular
            guard let file = Self.catalog.files.first(where: { $0.file == filename }) else { return nil }
            return font(url: root.appendingPathComponent("Cloud/\(family.id)/\(filename)"), faceIndex: selection.faceIndex, size: size, expectedHash: file.sha256)
        }
        let url = root.appendingPathComponent("Imported/\(selection.fileId).font")
        guard values.contains(where: { $0.id == importedId }) else { return nil }
        return font(url: url, faceIndex: selection.faceIndex, size: size, expectedHash: selection.fileId)
    }

    func font(prefix: String, size: CGFloat, weight: NSFont.Weight, italic: Bool) -> NSFont? {
        let files = Self.catalog.files.filter { $0.file.hasPrefix(prefix + "-") }
        let adobe = prefix == "SourceSans3" || prefix == "SourceSerif4"
        let suffix: String = weight >= .bold ? "Bold" : weight >= .semibold ? (adobe ? "Semibold" : "SemiBold") : weight >= .medium ? "Medium" : "Regular"
        let italicSuffix = adobe ? (suffix == "Regular" ? "It" : suffix + "It") : (suffix == "Regular" ? "Italic" : suffix + "Italic")
        let names = italic ? [italicSuffix, adobe ? "It" : "Italic", suffix, "Regular", "Variable"] : [suffix, "Regular", "Variable"]
        let matching = names.lazy.compactMap { name in files.first(where: { $0.file == "\(prefix)-\(name).ttf" }) }.first ?? files.first
        guard let file = matching else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return font(url: root.appendingPathComponent("Cloud/\(prefix)/\(file.file)"), faceIndex: 0, size: size, expectedHash: file.sha256)
    }

    private func font(url: URL, faceIndex: Int, size: CGFloat, expectedHash: String) -> NSFont? {
        if descriptors[url] == nil {
            guard let attributes = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = attributes.fileSize, size > 0, size <= Self.maximumImportBytes,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe), Self.hash(data) == expectedHash,
                  let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], !descriptors.isEmpty else { return nil }
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) { registered.insert(url) }
            self.descriptors[url] = descriptors
        }
        guard let descriptors = descriptors[url], descriptors.indices.contains(faceIndex) else { return nil }
        let font = CTFontCreateWithFontDescriptor(descriptors[faceIndex], size, nil)
        return font as NSFont
    }

    private func unregister(_ url: URL) {
        if registered.remove(url) != nil { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
        descriptors.removeValue(forKey: url)
    }

    private func createRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var excluded = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
    }

    private func publish() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: self) }
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension RegramFontStore {
    public func download(prefix: String) -> Signal<Double, RegramFontError> {
        let files = Self.catalog.files.filter { $0.file.hasPrefix(prefix + "-") }
        guard !files.isEmpty, files.allSatisfy({ $0.source.scheme == "https" && $0.file == URL(fileURLWithPath: $0.file).lastPathComponent }) else { return .fail(.unavailable) }
        return Signal { subscriber in
            let download = RegramFontDownload(files: files, progress: { subscriber.putNext($0) }, completion: { result in
                switch result {
                case let .success(stage):
                    self.lock.lock()
                    do {
                        try self.createRoot()
                        let directory = self.root.appendingPathComponent("Cloud", isDirectory: true)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        let destination = directory.appendingPathComponent(prefix, isDirectory: true)
                        let backup = directory.appendingPathComponent(".\(UUID().uuidString)", isDirectory: true)
                        let existed = FileManager.default.fileExists(atPath: destination.path)
                        for url in self.registered.filter({ $0.path.hasPrefix(destination.path + "/") }) { self.unregister(url) }
                        if existed { try FileManager.default.moveItem(at: destination, to: backup) }
                        do { try FileManager.default.moveItem(at: stage, to: destination) }
                        catch {
                            if existed { try? FileManager.default.moveItem(at: backup, to: destination) }
                            throw error
                        }
                        if existed { try? FileManager.default.removeItem(at: backup) }
                        self.version &+= 1
                        self.lock.unlock()
                        self.publish()
                        subscriber.putNext(1)
                        subscriber.putCompletion()
                    } catch { self.lock.unlock(); subscriber.putError(.storage) }
                    try? FileManager.default.removeItem(at: stage)
                case let .failure(error): subscriber.putError(error)
                }
            })
            download.start()
            return ActionDisposable { download.cancel() }
        }
    }
}

private final class RegramFontDownload: NSObject, URLSessionDownloadDelegate {
    private let files: [RegramCloudFont]
    private let progress: (Double) -> Void
    private let completion: (Result<URL, RegramFontError>) -> Void
    private let queue: OperationQueue
    private let stage = FileManager.default.temporaryDirectory.appendingPathComponent("RegramFonts-\(UUID().uuidString)", isDirectory: true)
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var index = 0
    private var finished = false
    private var archives: [URL: URL] = [:]

    init(files: [RegramCloudFont], progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, RegramFontError>) -> Void) {
        self.files = files
        self.progress = progress
        self.completion = completion
        self.queue = OperationQueue()
        self.queue.maxConcurrentOperationCount = 1
        self.queue.qualityOfService = .utility
    }

    func start() {
        queue.addOperation {
            do {
                try FileManager.default.createDirectory(at: self.stage.appendingPathComponent("Fonts"), withIntermediateDirectories: true)
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 30
                configuration.timeoutIntervalForResource = 600
                self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: self.queue)
                self.next()
            } catch { self.finish(.failure(.storage)) }
        }
    }

    func cancel() {
        queue.addOperation { self.finish(.failure(.cancelled)) }
    }

    private func next() {
        guard !finished else { return }
        guard index < files.count else { finish(.success(stage.appendingPathComponent("Fonts"))); return }
        let file = files[index]
        if let archive = archives[file.source] {
            do { try validate(archive, file: file); index += 1; next() }
            catch { finish(.failure(error as? RegramFontError ?? .integrity)) }
            return
        }
        task = session?.downloadTask(with: file.source)
        task?.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard !finished, downloadTask == task else { return }
        if totalBytesWritten > RegramFontStore.maximumDownloadBytes || totalBytesExpectedToWrite > RegramFontStore.maximumDownloadBytes { finish(.failure(.tooLarge)); return }
        let fraction = totalBytesExpectedToWrite > 0 ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : 0
        progress((Double(index) + fraction) / Double(files.count))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard !finished, downloadTask == task else { return }
        guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200, response.url?.scheme == "https" else { finish(.failure(.unavailable)); return }
        let file = files[index]
        do {
            let archive = stage.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: archive)
            try validate(archive, file: file)
            if file.archive_member != nil { archives[file.source] = archive }
            else { try? FileManager.default.removeItem(at: archive) }
            index += 1
            next()
        } catch { finish(.failure(error as? RegramFontError ?? .integrity)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished, task == self.task, error != nil else { return }
        finish(.failure(.unavailable))
    }

    private func validate(_ source: URL, file: RegramCloudFont) throws {
        guard let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= RegramFontStore.maximumDownloadBytes else { throw RegramFontError.tooLarge }
        let destination = stage.appendingPathComponent("Fonts/\(file.file)")
        if let member = file.archive_member, let archiveHash = file.archive_sha256 {
            guard RegramFontStore.hash(try Data(contentsOf: source, options: .mappedIfSafe)) == archiveHash, !member.hasPrefix("/"), !member.split(separator: "/").contains("..") else { throw RegramFontError.integrity }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-p", source.path, member]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, data.count == file.bytes, data.count <= RegramFontStore.maximumImportBytes else { throw RegramFontError.integrity }
            try data.write(to: destination, options: .atomic)
        } else { try FileManager.default.copyItem(at: source, to: destination) }
        let data = try Data(contentsOf: destination, options: .mappedIfSafe)
        guard data.count == file.bytes, RegramFontStore.hash(data) == file.sha256, let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor], !descriptors.isEmpty else { throw RegramFontError.integrity }
    }

    private func finish(_ result: Result<URL, RegramFontError>) {
        guard !finished else { return }
        finished = true
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        completion(result)
        try? FileManager.default.removeItem(at: stage)
    }
}
