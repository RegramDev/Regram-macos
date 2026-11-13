import Foundation
import SwiftSignalKit
import RegramCore

public func regramProtectedTranslation(text: String, to: String, accountId: Int64, settings: RegramAccountSettings, ranges: [RGTranslationLinkPlan.ProtectedRange], protectedIds: Set<Int>, context: [String] = [], permitsNetworkFallback: @escaping () -> Signal<Bool, NoError> = { .single(true) }, telegramTranslate: ((String, String) -> Signal<String, TranslateFetchError>)? = nil) -> Signal<(text: String, ranges: [RGTranslationLinkPlan.ProtectedRange]), TranslateFetchError> {
    let links = RGTranslationLinkPlan.literalLinkRanges(in: text).enumerated().map { RGTranslationLinkPlan.ProtectedRange(range: $0.element, id: -$0.offset - 1) }
    let plan = RGTranslationLinkPlan(text: text, ranges: ranges + links, protectedIds: protectedIds.union(links.map(\.id)))
    let signals: [Signal<String, TranslateFetchError>] = plan.segments.map { segment in
        if segment.id != nil || segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .single(segment.text) }
        return regramExternalTranslate(text: segment.text, to: to, accountId: accountId, settings: settings, context: context, permitsNetworkFallback: permitsNetworkFallback, telegramTranslate: telegramTranslate)
    }
    let backend = settings["translationBackend"].string
    let timeout: Double
    switch backend {
    case "llm": timeout = rgTranslationSegmentTimeout(utf16Length: text.utf16.count, maxChunkLength: 2000, chunkTimeout: 120)
    case "system": timeout = 120
    default: timeout = rgTranslationSegmentTimeout(utf16Length: text.utf16.count, maxChunkLength: 1000, chunkTimeout: 30)
    }
    return rgTranslateSequentially(signals, chunkTimeout: timeout) |> map { plan.restore(translations: $0) }
}
