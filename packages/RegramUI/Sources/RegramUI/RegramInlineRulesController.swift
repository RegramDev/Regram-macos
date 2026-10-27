import Foundation
import TGUIKit
import TelegramContext
import TelegramTheme
import SwiftSignalKit
import InputDataUI
import GeneralRows
import RegramCore
import RegramSignals
import ChatHistoryModel

public func RegramInlineRulesController(context: any AccountContextProtocol) -> InputDataController {
    let accountId = context.peerId.toInt64()
    RegramLinkMetadata.shared.refreshIfNeeded(engine: context.engine)
    let rules = Signal<[RegramMetadataInlineRule], NoError> { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: RGLinkPreviewRules.didChangeNotification, object: nil, queue: .main) { _ in
            subscriber.putNext(RegramLinkMetadata.shared.currentInlineBotRules())
        }
        subscriber.putNext(RegramLinkMetadata.shared.currentInlineBotRules())
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
    let signal = combineLatest(regramPreferenceChanges(accountId: accountId), rules, appearanceSignal) |> map { settings, rules, _ -> InputDataSignalValue in
        var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
        rows.append(.desc(sectionId: 1, index: 0, text: .plain(regramString("ios.features.InlineBots.Title")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        rows.append(.general(sectionId: 1, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("inlineBots.enabled"), data: .init(name: regramString("ios.features.AutoInlineBot.Enabled"), color: theme.colors.text, type: .switchable(settings["features.autoInlineBotEnabled"].bool), viewType: .singleItem, action: {
            RegramPreferences.shared.update(accountId: accountId) { $0["features.autoInlineBotEnabled"] = .bool(!settings["features.autoInlineBotEnabled"].bool) }
        })))
        rows.append(.desc(sectionId: 1, index: 2, text: .plain(regramString("ios.features.AutoInlineBot.Footer")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        rows.append(.sectionId(1, type: .normal))
        rows.append(.desc(sectionId: 2, index: 3, text: .plain(regramString("ios.features.InlineBotRules")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        for (index, rule) in rules.enumerated() {
            rows.append(.sectionId(Int32(index + 2), type: .normal))
            rows.append(.desc(sectionId: Int32(index + 3), index: Int32(index * 2 + 4), text: .plain("@" + rule.username), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            rows.append(.desc(sectionId: Int32(index + 3), index: Int32(index * 2 + 5), text: .plain(rule.rules.joined(separator: "\n\n")), data: .init(color: theme.colors.text, viewType: .textBottomItem)))
        }
        rows.append(.desc(sectionId: Int32(rules.count + 2), index: Int32(rules.count * 2 + 4), text: .plain(regramString("ios.features.InlineBotRules.Footer")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        return InputDataSignalValue(entries: rows)
    }
    return InputDataController(dataSignal: signal, title: regramString("ios.features.InlineBots.Title"), removeAfterDisappear: false, hasDone: false, identifier: "regram.inlineBots")
}
