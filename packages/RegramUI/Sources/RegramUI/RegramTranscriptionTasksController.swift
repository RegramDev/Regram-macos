import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import Postbox
import InputDataUI
import RegramServices

public func RegramTranscriptionTasksController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let tasks = RegramTranscriptionTasks.shared
    let signal = combineLatest(tasks.signal(accountId: accountId), appearanceSignal) |> map { values, _ -> InputDataSignalValue in
        var rows: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .desc(sectionId: 1, index: 0, text: .plain(regramString("transcription.tasksNotice")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem))
        ]
        if values.isEmpty {
            rows.append(.desc(sectionId: 1, index: 1, text: .plain(regramString("transcription.tasksEmpty")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        }
        for (index, value) in values.enumerated() {
            let id = value.key.messageId
            var actions = [ContextMenuItem(regramString("transcription.openMessage"), handler: {
                RegramUIHooks.shared.openMessage(context, MessageId(peerId: PeerId(id.peerId), namespace: id.namespace, id: id.id), value.threadId)
            })]
            if value.state == .running {
                actions.append(ContextMenuItem(regramString("cancel"), handler: { tasks.cancel(value.key) }))
            } else {
                actions.append(ContextMenuItem(regramString("transcription.retry"), handler: { tasks.retry(value.key) }))
            }
            rows.append(.general(sectionId: 1, index: Int32(index + 2), value: .none, error: nil, identifier: InputDataIdentifier("transcription_task_\(id.peerId)_\(id.namespace)_\(id.id)"), data: .init(name: regramString("transcription.message") + " #\(id.id)", color: theme.colors.text, type: .contextSelector(regramString("transcription.state." + value.state.rawValue), actions), viewType: values.count == 1 ? .singleItem : index == 0 ? .firstItem : index == values.count - 1 ? .lastItem : .innerItem, description: value.error)))
        }
        if values.contains(where: { $0.state != .running && $0.state != .interrupted }) {
            rows.append(.sectionId(1, type: .normal))
            rows.append(.general(sectionId: 2, index: Int32(values.count + 2), value: .none, error: nil, identifier: InputDataIdentifier("transcription_tasks_clear"), data: .init(name: regramString("transcription.clearFinished"), color: theme.colors.accent, type: .none, viewType: .singleItem, action: { tasks.clearFinished(accountId: accountId) })))
        }
        return InputDataSignalValue(entries: rows)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("transcription.tasks"), removeAfterDisappear: false, hasDone: false, identifier: "regram.transcriptionTasks")
    regramFocusSettings(controller, page: "transcriptionTasks", item: focusSetting)
    return controller
}
