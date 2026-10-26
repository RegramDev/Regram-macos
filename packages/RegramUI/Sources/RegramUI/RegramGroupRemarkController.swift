import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import InputDataUI
import RegramCore

public func RegramGroupRemarkController(context: any AccountContextProtocol, peerId: PeerId, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let initial = RGGroupRemarks.shared.name(accountId: accountId, peerId: peerId.toInt64()) ?? ""
    let state = ValuePromise(initial, ignoreRepeated: true)
    let current = Atomic(value: initial)
    let canSave = Atomic(value: false)
    let identifier = InputDataIdentifier("groupRemark.name")
    func update(_ value: String) { _ = current.swap(value); state.set(value) }
    let signal = combineLatest(context.account.postbox.peerView(id: peerId), state.get(), appearanceSignal) |> map { view, value, _ -> InputDataSignalValue in
        let peer = peerViewMainPeer(view)
        let title = (peer as? TelegramGroup)?.title ?? (peer as? TelegramChannel)?.title ?? ""
        _ = canSave.swap(peer is TelegramGroup || peer is TelegramChannel)
        let rows: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .desc(sectionId: 1, index: 0, text: .plain(String(format: regramString("GroupRemark.OriginalName"), title)), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
            .input(sectionId: 1, index: 1, value: .string(value), error: nil, identifier: identifier, mode: .plain, data: .init(viewType: .singleItem, rightItem: .action(theme.icons.recentDismiss, .clearText)), placeholder: nil, inputPlaceholder: title, filter: { $0 }, limit: Int32(RGGroupRemarks.maximumLength)),
            .desc(sectionId: 1, index: 2, text: .plain(regramString("GroupRemark.Notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
            .sectionId(1, type: .normal),
            .general(sectionId: 2, index: 3, value: .none, error: nil, identifier: InputDataIdentifier("groupRemark.clear"), data: .init(name: regramString("GroupRemark.UseOriginalName"), color: theme.colors.accent, type: .none, viewType: .singleItem, action: { update("") }))
        ]
        return InputDataSignalValue(entries: rows)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("GroupRemark.Title"), validateData: { data in
        guard canSave.with({ $0 }) else { return .fail(.none) }
        RGGroupRemarks.shared.setName(data[identifier]?.stringValue ?? current.with { $0 }, accountId: accountId, peerId: peerId.toInt64())
        return .success(.navigationBack)
    }, updateDatas: { data in
        if let value = data[identifier]?.stringValue { update(value) }
        return .fail(.none)
    }, updateDoneValue: { _ in
        let enabled = canSave.with { $0 }
        return { $0(enabled ? .enabled(strings().modalSave) : .disabled(strings().modalSave)) }
    }, doneString: { strings().modalSave })
    regramFocusSettings(controller, page: "groupRemark", item: focusSetting)
    return controller
}
