import Foundation
import SwiftSignalKit
import RegramCore

public enum RegramImageTranslationError: Error, Equatable {
    case limitExceeded
    case outdated
    case failed
}

public enum RegramImageTranslationBudget {
    public static let maximumRegions = 128
    public static let maximumRequests = 24
    public static let maximumCharacters = 12000
    public static let maximumRegionCharacters = 1000

    public static func hasText(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }
}

public func regramTranslateImageRegions(_ regions: [String], to: String, accountId: Int64, settings: RegramAccountSettings, permitsTranslation: @escaping () -> Signal<Bool, NoError>, telegramTranslate: @escaping (String, String) -> Signal<String, TranslateFetchError>) -> Signal<[String], RegramImageTranslationError> {
    guard regions.count <= RegramImageTranslationBudget.maximumRegions,
          regions.allSatisfy({ $0.utf16.count <= RegramImageTranslationBudget.maximumRegionCharacters }),
          regions.reduce(0, { $0 + $1.utf16.count }) <= RegramImageTranslationBudget.maximumCharacters else { return .fail(.limitExceeded) }
    var jobs: [String] = []
    var jobIndices: [String: Int] = [:]
    let indices = regions.map { text -> Int? in
        guard RegramImageTranslationBudget.hasText(text) else { return nil }
        if let index = jobIndices[text] { return index }
        let index = jobs.count
        jobIndices[text] = index
        jobs.append(text)
        return index
    }
    guard jobs.count <= RegramImageTranslationBudget.maximumRequests else { return .fail(.limitExceeded) }
    guard !jobs.isEmpty else { return .single(regions) }
    let signals = jobs.map { text in
        regramExternalTranslate(text: text, to: to, accountId: accountId, settings: settings, permitsNetworkFallback: permitsTranslation, telegramTranslate: telegramTranslate)
        |> mapToSignal { value -> Signal<String, TranslateFetchError> in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .fail(.network) : .single(value)
        }
    }
    return rgTranslateSequentially(signals, chunkTimeout: ["llm", "system"].contains(settings["translationBackend"].string) ? 120 : 30)
    |> mapError { error -> RegramImageTranslationError in
        switch error { case .outdated: return .outdated; case .network: return .failed }
    }
    |> map { values in regions.enumerated().map { index, original in indices[index].map { values[$0] } ?? original } }
}
