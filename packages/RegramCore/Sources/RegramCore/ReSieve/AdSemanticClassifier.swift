import CoreML
import Foundation
import NaturalLanguage

public struct RGAdSemanticResult: Codable, Equatable {
    public let predictions: [RGAdPrediction]
    public let buttonIds: Set<String>
    public let threshold: Double
    public let entireMessage: Bool
    public let completed: Bool
    public let promotionalQuotes: [RGAdRange]
    public init(
        predictions: [RGAdPrediction] = [], buttonIds: Set<String> = [], threshold: Double = 1, entireMessage: Bool = false,
        completed: Bool = true, promotionalQuotes: [RGAdRange] = []
    ) {
        self.predictions = predictions
        self.buttonIds = buttonIds
        self.threshold = threshold
        self.entireMessage = entireMessage
        self.completed = completed
        self.promotionalQuotes = promotionalQuotes
    }
}

@available(macOS 10.15, *)
public final class RGAdSemanticClassifier {
    public static let shared = RGAdSemanticClassifier()
    private static let contentThreshold = 0.2
    private struct Manifest: Decodable {
        let version: Int
        let sequenceLength: Int
        let threshold: Double
        let labels: [String]
    }
    private struct Loaded {
        let model: MLModel
        let tokenizer: RGAdTokenizer
        let threshold: Double
        let ids: MLMultiArray
        let mask: MLMultiArray
        let features: MLDictionaryFeatureProvider
    }
    private struct Score {
        let probability: Double
        let isExact: Bool
    }
    private let lock = NSLock()
    private let resourceDirectory: URL?
    private var loaded: Loaded?
    private var acceleratedModel: MLModel?
    private var retryAfter: TimeInterval = 0
    private var scores = RGAdBoundedCache<String, Score>(countLimit: 2048, costLimit: 1792 * 1024)
    private var windowScores = RGAdBoundedCache<[Int32], Score>(countLimit: 512, costLimit: 256 * 1024)

    public init(resourceDirectory: URL? = nil) { self.resourceDirectory = resourceDirectory }

    private func resource(_ name: String, _ ext: String) -> URL? {
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

    private func load() throws -> Loaded {
        guard ProcessInfo.processInfo.systemUptime >= retryAfter else { throw RGAdFilterError.invalidModel }
        if let loaded { return loaded }
        guard let manifestURL = resource("RGAdModel", "json"), let vocabularyURL = resource("RGAdVocabulary", "txt") else {
            throw RGAdFilterError.invalidModel
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.version == 1, manifest.labels == ["content", "promotion"], manifest.threshold.isFinite,
            (0.8...0.9999).contains(manifest.threshold)
        else { throw RGAdFilterError.invalidModel }
        let tokenizer = try RGAdTokenizer(
            vocabulary: String(contentsOf: vocabularyURL, encoding: .utf8), sequenceLength: manifest.sequenceLength)
        let modelURL: URL
        if let compiled = resource("ReSieve", "mlmodelc") {
            modelURL = compiled
        } else if let raw = resource("ReSieve", "mlmodel") {
            modelURL = try MLModel.compileModel(at: raw)
        } else {
            throw RGAdFilterError.invalidModel
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        guard model.modelDescription.inputDescriptionsByName["input_ids"] != nil,
            model.modelDescription.inputDescriptionsByName["attention_mask"] != nil,
            model.modelDescription.outputDescriptionsByName["probabilities"] != nil
        else { throw RGAdFilterError.invalidModel }
        let ids = try MLMultiArray(shape: [1, NSNumber(value: tokenizer.sequenceLength)], dataType: .int32)
        let mask = try MLMultiArray(shape: ids.shape, dataType: .int32)
        let features = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: ids), "attention_mask": MLFeatureValue(multiArray: mask),
        ])
        let value = Loaded(model: model, tokenizer: tokenizer, threshold: manifest.threshold, ids: ids, mask: mask, features: features)
        loaded = value
        loadAcceleratedModel(at: modelURL, for: model)
        return value
    }

    private func loadAcceleratedModel(at url: URL, for fallback: MLModel) {
        #if arch(arm64)
            guard #available(macOS 13, *) else { return }
            DispatchQueue.global(qos: .utility).async { [weak self, weak fallback] in
                guard let fallback else { return }
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .cpuAndNeuralEngine
                guard let model = try? MLModel(contentsOf: url, configuration: configuration), let self else { return }
                self.lock.lock()
                defer { self.lock.unlock() }
                if self.loaded?.model === fallback { self.acceleratedModel = model }
            }
        #endif
    }

    private func confidence(from model: MLModel, features: MLDictionaryFeatureProvider) throws -> Double {
        let output = try model.prediction(from: features)
        guard let probabilities = output.featureValue(for: "probabilities")?.multiArrayValue, probabilities.count == 2 else {
            throw RGAdFilterError.invalidPrediction
        }
        let score = probabilities[1].doubleValue
        guard score.isFinite, (0...1).contains(score) else { throw RGAdFilterError.invalidPrediction }
        return score
    }

    private func acceleratedContent(_ features: MLDictionaryFeatureProvider) -> Bool {
        guard let model = acceleratedModel else { return false }
        do {
            return try confidence(from: model, features: features) <= 0.1
        } catch {
            acceleratedModel = nil
            return false
        }
    }

    private func probability(of key: String, using value: Loaded, minimumLength: Int = 4, forClassification: Bool = false) throws -> Double? {
        guard key.count >= minimumLength else { return nil }
        if let cached = scores[key], forClassification || cached.isExact { return cached.probability }
        guard let windows = value.tokenizer.windows(key), windows.count <= 8 else { return nil }
        var minimum = 1.0
        var isExact = true
        for (windowIndex, window) in windows.enumerated() {
            guard window.count == value.ids.count, value.mask.count == value.ids.count else { throw RGAdFilterError.invalidPrediction }
            let score: Score
            if let cached = windowScores[window], forClassification || cached.isExact {
                score = cached
            } else {
                let ids = value.ids.dataPointer.assumingMemoryBound(to: Int32.self)
                let mask = value.mask.dataPointer.assumingMemoryBound(to: Int32.self)
                for (index, token) in window.enumerated() {
                    ids[index] = token
                    mask[index] = token == 0 ? 0 : 1
                }
                if forClassification, acceleratedContent(value.features) {
                    score = Score(probability: Self.contentThreshold, isExact: false)
                } else {
                    score = Score(probability: try confidence(from: value.model, features: value.features), isExact: true)
                }
                windowScores.insert(score, for: window, cost: window.count * MemoryLayout<Int32>.stride + 128)
            }
            minimum = min(minimum, score.probability)
            isExact = isExact && score.isExact
            if forClassification, minimum <= Self.contentThreshold, windowIndex + 1 < windows.count {
                isExact = false
                break
            }
        }
        scores.insert(Score(probability: minimum, isExact: isExact), for: key, cost: key.utf8.count * 2 + 128)
        return minimum
    }

    public func reduceMemoryPressure() {
        lock.lock()
        defer { lock.unlock() }
        scores.removeAll()
        windowScores.removeAll()
        loaded = nil
        acceleratedModel = nil
    }

    public func probability(_ text: String) throws -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return try probability(of: RGAdTokenizer.normalize(text), using: load())
    }

    public func prepareModel() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do { return try probability(of: RGAdTokenizer.normalize("本机模型运行检测"), using: load()) != nil } catch {
            if ProcessInfo.processInfo.systemUptime >= retryAfter { retryAfter = ProcessInfo.processInfo.systemUptime + 60 }
            return false
        }
    }

    public func predict(_ input: RGAdInput) -> RGAdSemanticResult {
        guard input.text.utf16.count <= 65_536, input.entities.count <= 2048,
            input.buttons.count <= 128, input.buttons.flatMap({ $0 }).count <= 128,
            input.buttons.flatMap({ $0 }).allSatisfy({ $0.title.utf16.count <= 1024 })
        else { return RGAdSemanticResult() }
        var normalizedTexts: [String: String] = [:]
        var normalizedBytes = 0
        func normalize(_ text: String) -> String {
            if let normalized = normalizedTexts[text] { return normalized }
            let normalized = RGAdTokenizer.normalize(text)
            let cost = (text.utf8.count + normalized.utf8.count) * 2 + 128
            if normalizedTexts.count < 128, cost <= 256 * 1024 - normalizedBytes {
                normalizedTexts[text] = normalized
                normalizedBytes += cost
            }
            return normalized
        }
        func supportsLanguage(_ text: String) -> Bool {
            let normalized = normalize(text)
            let language = NLLanguageRecognizer.dominantLanguage(for: normalized)
            if language == .simplifiedChinese || language == .traditionalChinese { return true }
            if language == .japanese || language == .korean
                || normalized.unicodeScalars.contains(where: {
                    (0x3041...0x3096).contains($0.value) || (0x30a1...0x30fa).contains($0.value) || (0xac00...0xd7a3).contains($0.value)
                })
            {
                return false
            }
            let han = normalized.unicodeScalars.filter { (0x3400...0x9fff).contains($0.value) }.count
            let letters = normalized.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            return han >= (normalized.count <= 128 ? 4 : 24) && han * 4 >= letters
        }
        let wholeLanguageSupported = supportsLanguage(input.text)
        guard
            wholeLanguageSupported
                || (input.text + input.buttons.flatMap({ $0 }).map(\.title).joined()).unicodeScalars.contains(where: {
                    (0x3400...0x9fff).contains($0.value)
                })
        else { return RGAdSemanticResult() }
        lock.lock()
        defer { lock.unlock() }
        do {
            let value = try load()
            func classificationScore(_ text: String, minimumLength: Int = 4) throws -> Double? {
                try probability(of: normalize(text), using: value, minimumLength: minimumLength, forClassification: true)
            }
            let source = input.text as NSString
            func hasSemanticWords(_ range: RGAdRange) -> Bool {
                let destinations = input.entities.filter { entity in
                    [.link, .mention].contains(entity.kind) && entity.range.lower < entity.range.upper && range.contains(entity.range)
                        && RGAdFilter.normalizedTarget(source.substring(with: entity.range.nsRange)) != nil
                }.sorted { $0.range.lower < $1.range.lower }
                var text = ""
                var cursor = range.lower
                for entity in destinations {
                    if cursor < entity.range.lower {
                        text += source.substring(with: NSRange(location: cursor, length: entity.range.lower - cursor))
                    }
                    cursor = max(cursor, entity.range.upper)
                }
                if cursor < range.upper { text += source.substring(with: NSRange(location: cursor, length: range.upper - cursor)) }
                return normalize(text).unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) })
            }
            var predictions: [RGAdPrediction] = []
            var promotionalQuotes: [RGAdRange] = []
            let navigationRows = RGAdFilter.navigationRows(input)
            let navigation = Set(navigationRows.values.flatMap { $0 })
            let paragraphs =
                (RGAdFilter.semanticRanges(input.text, entities: input.entities).filter { range in
                    !navigationRows.keys.contains(where: { $0.intersects(range) })
                } + Array(navigation)).sorted { $0.lower < $1.lower }
            let blocks = RGAdFilter.contextRanges(input.text)
            guard paragraphs.count <= 128 else { return RGAdSemanticResult() }
            var hasContent = !wholeLanguageSupported
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            let substantive = paragraphs.filter { normalize(source.substring(with: $0.nsRange)).count >= 4 }
            let interactive = input.buttons.flatMap { $0 }.filter { $0.target == nil }.count >= 2
            let disclosedProse = input.entities.contains(where: { $0.kind == .code }) && !RGAdDisclosure.ranges(input).isEmpty
            var blockScores: [RGAdRange: Double] = [:]
            for block in blocks {
                guard ProcessInfo.processInfo.systemUptime <= deadline else { return RGAdSemanticResult(completed: false) }
                if !wholeLanguageSupported && !supportsLanguage(source.substring(with: block.nsRange)) { continue }
                if let score = try classificationScore(source.substring(with: block.nsRange)) { blockScores[block] = score }
            }
            if wholeLanguageSupported, blocks.count == 1, let block = blocks.first,
                let score = blockScores[block], score >= max(0.999, value.threshold),
                !substantive.isEmpty, navigation.isEmpty,
                !input.entities.contains(where: { [.code, .quote].contains($0.kind) }),
                input.buttons.flatMap({ $0 }).allSatisfy({ RGAdFilter.normalizedTarget($0.target) != nil }),
                ProcessInfo.processInfo.systemUptime <= deadline
            {
                return RGAdSemanticResult(
                    predictions: [RGAdPrediction(range: RGAdRange(0, source.length), confidence: score)],
                    buttonIds: Set(input.buttons.flatMap({ $0 }).map(\.id)), threshold: value.threshold, entireMessage: true)
            }
            if blockScores.count >= 2, blockScores.values.allSatisfy({ $0 <= Self.contentThreshold }) { hasContent = true }
            let introductoryQuote: RGAdRange? = {
                guard blocks.count >= 2, let first = blocks.first, (blockScores[first] ?? 1) <= Self.contentThreshold,
                    normalize(source.substring(with: first.nsRange)).unicodeScalars.filter({
                        (0x3400...0x9fff).contains($0.value)
                    }).count >= 12,
                    !input.entities.contains(where: { [.quote, .code].contains($0.kind) && $0.range.intersects(first) }),
                    input.entities.contains(where: { [.quote, .code].contains($0.kind) && blocks[1].contains($0.range) })
                else { return nil }
                return blocks[1]
            }()
            if introductoryQuote != nil { hasContent = true }
            for range in paragraphs {
                if ProcessInfo.processInfo.systemUptime > deadline {
                    hasContent = true
                    break
                }
                guard
                    !input.entities.contains(where: {
                        $0.kind == .code && $0.range.intersects(range) && !RGAdFilter.isInlineCodeLabel($0, source: source)
                            && !(disclosedProse && RGAdDisclosure.isProseBlock($0, source: source))
                    })
                else {
                    hasContent = true
                    continue
                }
                let text = source.substring(with: range.nsRange)
                if !hasSemanticWords(range) { continue }
                if !wholeLanguageSupported && !supportsLanguage(text) { continue }
                let score = try classificationScore(text, minimumLength: navigation.contains(range) ? 2 : 4)
                let quoted = input.entities.contains { $0.kind == .quote && $0.range.intersects(range) }
                var contextualLead = true
                if range == substantive.first, substantive.count >= 3, let score, score >= value.threshold {
                    let lead = RGAdRange(range.lower, blocks.count >= 2 ? blocks[1].upper : substantive[1].upper)
                    contextualLead = (try classificationScore(source.substring(with: lead.nsRange)) ?? 0) >= value.threshold
                    if !contextualLead, score >= max(0.99, value.threshold),
                        let reference = input.entities.first(where: { entity in
                            entity.kind == .link && range.contains(entity.range)
                                && normalize(source.substring(with: entity.range.nsRange)) == normalize(text)
                        }), let target = RGAdFilter.normalizedTarget(reference.value)
                    {
                        for button in input.buttons.flatMap({ $0 }) where RGAdFilter.normalizedTarget(button.target) == target {
                            guard ProcessInfo.processInfo.systemUptime <= deadline else { break }
                            if (try classificationScore(button.title) ?? 0) >= max(0.99, value.threshold) {
                                contextualLead = true
                                break
                            }
                        }
                    }
                }
                let blockIndex = blocks.firstIndex(where: { $0.contains(range) })
                let contextualBlock = blockIndex.flatMap { blockScores[blocks[$0]] } ?? 0
                var contextualNeighbors = true
                let length = normalize(text).unicodeScalars.filter({ CharacterSet.alphanumerics.contains($0) }).count
                if let score, score >= value.threshold, blocks.count > 1, let blockIndex,
                    !input.entities.contains(where: { [.link, .mention].contains($0.kind) && $0.range.intersects(range) })
                {
                    let neighbors = RGAdRange(blocks[max(0, blockIndex - 1)].lower, blocks[min(blocks.count - 1, blockIndex + 1)].upper)
                    contextualNeighbors = (try classificationScore(source.substring(with: neighbors.nsRange)) ?? 0) >= value.threshold
                    if length < 48, (try classificationScore(input.text) ?? 0) <= Self.contentThreshold { contextualNeighbors = false }
                }
                if let score, score >= value.threshold, (4...48).contains(length), length >= 12 || contextualBlock <= Self.contentThreshold || score < 0.99,
                    !navigation.contains(range), blocks.count > 1, let blockIndex,
                    let reference = input.entities.first(where: { entity in
                        entity.kind == .link && range.contains(entity.range)
                            && RGAdFilter.normalizedTarget(source.substring(with: entity.range.nsRange)) == nil
                            && normalize(source.substring(with: entity.range.nsRange)) == normalize(text)
                    }), (try classificationScore(input.text) ?? 1) <= Self.contentThreshold
                {
                    let neighbors = RGAdRange(blocks[max(0, blockIndex - 1)].lower, blocks[min(blocks.count - 1, blockIndex + 1)].upper)
                    if (try classificationScore(source.substring(with: neighbors.nsRange)) ?? 1) <= Self.contentThreshold {
                        let target = RGAdFilter.normalizedTarget(reference.value)
                        var promotionalAction = false
                        for button in input.buttons.flatMap({ $0 })
                        where target != nil && RGAdFilter.normalizedTarget(button.target) == target {
                            guard ProcessInfo.processInfo.systemUptime <= deadline else { break }
                            if let actionScore = try classificationScore(button.title), actionScore >= 0.5 {
                                promotionalAction = true
                                if actionScore >= max(0.99, value.threshold), contextualBlock >= max(0.99, value.threshold) {
                                    contextualLead = true
                                }
                                break
                            }
                        }
                        if !promotionalAction { contextualNeighbors = false }
                    }
                }
                let linkedCaption =
                    length < 48 && input.entities.contains(where: { [.link, .mention].contains($0.kind) && range.contains($0.range) })
                if let score, score >= value.threshold, contextualBlock >= value.threshold || linkedCaption, !quoted, contextualLead,
                    contextualNeighbors
                {
                    predictions.append(RGAdPrediction(range: range, confidence: score))
                }
                if score == nil && length >= 8 {
                    hasContent = true
                } else if (score ?? 1) <= Self.contentThreshold, length >= 64 {
                    if let blockIndex, (blockScores[blocks[blockIndex]] ?? 1) <= Self.contentThreshold {
                        let neighbors = RGAdRange(blocks[max(0, blockIndex - 1)].lower, blocks[min(blocks.count - 1, blockIndex + 1)].upper)
                        if (try classificationScore(source.substring(with: neighbors.nsRange)) ?? 0) <= Self.contentThreshold {
                            var belongsToOffer = false
                            if ProcessInfo.processInfo.systemUptime <= deadline,
                                let offer = blocks.prefix(blockIndex).last(where: { (blockScores[$0] ?? 0) >= max(0.99, value.threshold) }),
                                (try classificationScore(input.text) ?? 0) >= max(0.99, value.threshold)
                            {
                                let context =
                                    source.substring(with: offer.nsRange) + "\n\n" + source.substring(with: blocks[blockIndex].nsRange)
                                belongsToOffer = (try classificationScore(context) ?? 0) >= max(0.99, value.threshold)
                            }
                            if !belongsToOffer { hasContent = true }
                        }
                    }
                }
                if interactive, (score ?? 1) <= Self.contentThreshold, length >= 8,
                    contextualBlock <= Self.contentThreshold || input.entities.contains(where: { $0.kind == .link && range.contains($0.range) })
                {
                    hasContent = true
                }
                if range == substantive.first, (score ?? 1) <= Self.contentThreshold, length >= 12,
                    let blockIndex, contextualBlock <= Self.contentThreshold, blocks.indices.contains(blockIndex + 1)
                {
                    let reference = blocks[blockIndex + 1]
                    if !hasSemanticWords(reference) {
                        let referenceTargets = Set(
                            input.entities.compactMap { entity -> String? in
                                guard entity.kind == .link, reference.contains(entity.range) else { return nil }
                                return RGAdFilter.normalizedTarget(entity.value ?? source.substring(with: entity.range.nsRange))
                            })
                        if !referenceTargets.isEmpty,
                            blocks.dropFirst(blockIndex + 2).contains(where: { block in
                                guard (blockScores[block] ?? 0) >= value.threshold else { return false }
                                return input.entities.contains { entity in
                                    guard entity.kind == .link, block.contains(entity.range),
                                        let target = RGAdFilter.normalizedTarget(
                                            entity.value ?? source.substring(with: entity.range.nsRange))
                                    else { return false }
                                    return !referenceTargets.contains(target)
                                }
                            })
                        {
                            hasContent = true
                        }
                    }
                }
            }
            for block in blocks {
                guard ProcessInfo.processInfo.systemUptime <= deadline else { break }
                guard let score = blockScores[block], score >= value.threshold,
                    !input.entities.contains(where: { [.code, .quote].contains($0.kind) && $0.range.intersects(block) }),
                    input.entities.contains(where: { [.link, .mention].contains($0.kind) && block.contains($0.range) })
                else { continue }
                let units = paragraphs.filter {
                    block.contains($0) && hasSemanticWords($0) && normalize(source.substring(with: $0.nsRange)).count >= 4
                }
                guard units.count >= 2, !units.contains(where: { navigation.contains($0) }) else { continue }
                var minimum = score
                for unit in units {
                    guard ProcessInfo.processInfo.systemUptime <= deadline,
                        let part = try classificationScore(source.substring(with: unit.nsRange))
                    else {
                        minimum = 0
                        break
                    }
                    minimum = min(minimum, part)
                    if minimum < value.threshold { break }
                }
                if minimum >= value.threshold { predictions.append(RGAdPrediction(range: block, confidence: minimum)) }
            }
            for units in navigationRows.values {
                for (index, range) in units.enumerated() {
                    guard ProcessInfo.processInfo.systemUptime <= deadline else { break }
                    let text = source.substring(with: range.nsRange)
                    guard (2...3).contains(normalize(text).count),
                        let shortScore = try classificationScore(text, minimumLength: 2), shortScore >= 0.99
                    else { continue }
                    for neighborIndex in [index - 1, index + 1] where units.indices.contains(neighborIndex) {
                        let neighbor = units[neighborIndex]
                        guard let known = predictions.first(where: { $0.range.contains(neighbor) && $0.confidence >= value.threshold })
                        else { continue }
                        let combined = RGAdRange(min(range.lower, neighbor.lower), max(range.upper, neighbor.upper))
                        if let score = try classificationScore(source.substring(with: combined.nsRange)), score >= value.threshold {
                            predictions.append(RGAdPrediction(range: combined, confidence: min(score, known.confidence)))
                        }
                    }
                }
            }
            for (index, block) in blocks.enumerated() where index > 0 && index + 1 < blocks.count {
                guard ProcessInfo.processInfo.systemUptime <= deadline else { break }
                guard let score = blockScores[block], score >= max(0.99, value.threshold),
                    !input.entities.contains(where: { [.code, .quote].contains($0.kind) && $0.range.intersects(block) }),
                    let menu = navigationRows.first(where: { blocks[index + 1].contains($0.key) })?.value
                else { continue }
                let commercialMenu = menu.filter { unit in
                    predictions.contains(where: { $0.range.contains(unit) && $0.confidence >= max(0.99, value.threshold) })
                }
                guard commercialMenu.count >= 2 else { continue }
                let units = paragraphs.filter {
                    block.contains($0) && hasSemanticWords($0) && normalize(source.substring(with: $0.nsRange)).count >= 4
                }
                guard !units.isEmpty, !units.contains(where: { navigation.contains($0) }) else { continue }
                var minimum = score
                for unit in units {
                    guard ProcessInfo.processInfo.systemUptime <= deadline,
                        let part = try classificationScore(source.substring(with: unit.nsRange))
                    else {
                        minimum = 0
                        break
                    }
                    minimum = min(minimum, part)
                    if minimum < value.threshold { break }
                }
                if minimum >= value.threshold, ProcessInfo.processInfo.systemUptime <= deadline {
                    let joint =
                        source.substring(with: block.nsRange) + "\n"
                        + commercialMenu.map { source.substring(with: $0.nsRange) }.joined(separator: " ")
                    if let contextual = try classificationScore(joint), contextual >= max(0.99, value.threshold) {
                        predictions.append(RGAdPrediction(range: block, confidence: min(minimum, contextual)))
                    }
                }
            }
            for (index, block) in blocks.enumerated() where index > 0 && index + 1 < blocks.count {
                guard ProcessInfo.processInfo.systemUptime <= deadline else { break }
                guard let score = blockScores[block], score >= max(0.99, value.threshold),
                    block != introductoryQuote,
                    input.entities.contains(where: { $0.kind == .quote && block.contains($0.range) }),
                    !input.entities.contains(where: { $0.kind == .code && $0.range.intersects(block) }),
                    let menu = navigationRows.first(where: { blocks[index + 1].contains($0.key) })?.value,
                    menu.filter({ unit in
                        predictions.contains(where: { $0.range.contains(unit) && $0.confidence >= max(0.99, value.threshold) })
                    }).count >= 2
                else { continue }
                let units = paragraphs.filter {
                    block.contains($0) && hasSemanticWords($0) && normalize(source.substring(with: $0.nsRange)).count >= 4
                }
                guard units.count >= 2 else { continue }
                var allCommercial = true
                for unit in units {
                    guard ProcessInfo.processInfo.systemUptime <= deadline,
                        (try classificationScore(source.substring(with: unit.nsRange)) ?? 0) >= value.threshold
                    else {
                        allCommercial = false
                        break
                    }
                }
                let context = source.substring(with: blocks[index - 1].nsRange)
                let quote = source.substring(with: block.nsRange).trimmingCharacters(in: .whitespacesAndNewlines)
                let commercialMenu = menu.filter { unit in
                    predictions.contains(where: { $0.range.contains(unit) && $0.confidence >= max(0.99, value.threshold) })
                }
                .map { source.substring(with: $0.nsRange).trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " ")
                guard quote.count <= 64 else { continue }
                let framed =
                    "上文：" + String(context.trimmingCharacters(in: .whitespacesAndNewlines).suffix(32))
                    + "\n引用：" + quote + "\n后续入口：" + String(commercialMenu.prefix(16))
                if allCommercial, ProcessInfo.processInfo.systemUptime <= deadline,
                    let contextual = try classificationScore(framed), contextual >= max(0.99, value.threshold)
                {
                    predictions.append(RGAdPrediction(range: block, confidence: min(score, contextual)))
                    promotionalQuotes.append(block)
                }
            }
            let lines = RGAdFilter.paragraphRanges(input.text)
            for (index, line) in lines.enumerated() where RGAdFilter.isSeparator(source.substring(with: line.nsRange)) {
                guard ProcessInfo.processInfo.systemUptime <= deadline else { break }
                let footer = RGAdRange(line.lower, source.length)
                guard footer.upper - footer.lower <= 2048, lines.count - index <= 32,
                    !input.entities.contains(where: { [.code, .quote].contains($0.kind) && $0.range.intersects(footer) })
                else { continue }
                var scores: [Double] = []
                var footerTexts: [String] = []
                var complete = true
                for candidate in lines[(index + 1)...] {
                    guard ProcessInfo.processInfo.systemUptime <= deadline else {
                        complete = false
                        break
                    }
                    let text = source.substring(with: candidate.nsRange)
                    if !normalize(text).unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
                        continue
                    }
                    if !hasSemanticWords(candidate) { continue }
                    if !wholeLanguageSupported && !supportsLanguage(text) {
                        complete = false
                        break
                    }
                    guard let score = try classificationScore(text), score >= value.threshold else {
                        complete = false
                        break
                    }
                    scores.append(score)
                    footerTexts.append(text)
                }
                if complete, !scores.isEmpty, let score = try classificationScore(footerTexts.joined(separator: "\n")),
                    score >= value.threshold
                {
                    predictions.append(RGAdPrediction(range: footer, confidence: min(score, scores.min() ?? score)))
                    break
                }
            }
            var entireMessage = false
            var normalIntroduction = false
            var projectionThreshold = value.threshold
            let hasBodyBeyondNavigation = navigation.isEmpty || substantive.contains(where: { !navigation.contains($0) })
            if !hasContent, !substantive.isEmpty, hasBodyBeyondNavigation, ProcessInfo.processInfo.systemUptime <= deadline {
                let whole = try classificationScore(input.text) ?? 0
                let meaningfulBlocks = blocks.filter {
                    hasSemanticWords($0) && normalize(source.substring(with: $0.nsRange)).count >= 4
                }
                if whole >= 0.99, meaningfulBlocks.count >= 2,
                    meaningfulBlocks.allSatisfy({ (blockScores[$0] ?? 0) >= 0.99 }),
                    meaningfulBlocks.filter({ (blockScores[$0] ?? 0) >= value.threshold }).count >= 2
                {
                    projectionThreshold = min(value.threshold, 0.99)
                }
                if whole >= max(0.99, projectionThreshold), ProcessInfo.processInfo.systemUptime <= deadline {
                    let prefixBlocks = blocks.prefix { (blockScores[$0] ?? 1) <= Self.contentThreshold && hasSemanticWords($0) }
                    if prefixBlocks.count >= 3, let first = prefixBlocks.first, let last = prefixBlocks.last {
                        let prefix = source.substring(with: RGAdRange(first.lower, last.upper).nsRange)
                        if normalize(prefix).unicodeScalars.filter({ CharacterSet.alphanumerics.contains($0) }).count >= 24 {
                            normalIntroduction = (try classificationScore(prefix) ?? 1) <= Self.contentThreshold
                        }
                    }
                    if !normalIntroduction, ProcessInfo.processInfo.systemUptime <= deadline {
                        predictions.append(RGAdPrediction(range: RGAdRange(0, input.text.utf16.count), confidence: whole))
                        entireMessage = true
                    }
                }
            }
            var buttons = Set<String>()
            for button in input.buttons.flatMap({ $0 }) {
                if entireMessage {
                    buttons.insert(button.id)
                } else if RGAdFilter.normalizedTarget(button.target) != nil, ProcessInfo.processInfo.systemUptime <= deadline,
                    supportsLanguage(button.title), let score = try classificationScore(button.title), score >= value.threshold
                {
                    buttons.insert(button.id)
                }
            }
            let actions = input.buttons.flatMap { $0 }
            if !entireMessage, !normalIntroduction, !actions.isEmpty, actions.count <= 4,
                (4...64).contains(normalize(input.text).count),
                !input.entities.contains(where: { [.code, .quote].contains($0.kind) }),
                actions.allSatisfy({ RGAdFilter.normalizedTarget($0.target) != nil && buttons.contains($0.id) }),
                ProcessInfo.processInfo.systemUptime <= deadline,
                (try classificationScore(input.text) ?? 0) >= 0.5
            {
                let combined = input.text + "\n" + actions.map(\.title).joined(separator: "\n")
                if let score = try classificationScore(combined), score >= max(0.99, value.threshold) {
                    predictions.append(RGAdPrediction(range: RGAdRange(0, source.length), confidence: score))
                    entireMessage = true
                }
            }
            return RGAdSemanticResult(
                predictions: predictions, buttonIds: buttons, threshold: entireMessage ? projectionThreshold : value.threshold,
                entireMessage: entireMessage, completed: ProcessInfo.processInfo.systemUptime <= deadline,
                promotionalQuotes: promotionalQuotes)
        } catch {
            if ProcessInfo.processInfo.systemUptime >= retryAfter { retryAfter = ProcessInfo.processInfo.systemUptime + 60 }
            return RGAdSemanticResult(completed: false)
        }
    }
}
