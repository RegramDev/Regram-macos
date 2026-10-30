import Cocoa
import TGUIKit
import SwiftSignalKit
import InputDataUI
import GeneralRows
import TelegramTheme
import Localization

enum RegramSelectionStyle { case multiple, single }

private final class RegramFormBinding {
    weak var controller: InputDataController?
    private let themeDisposable = MetaDisposable()
    private weak var currentTheme: TelegramPresentationTheme?

    func observeTheme() {
        themeDisposable.set((appearanceSignal |> deliverOnMainQueue).start(next: { [weak self] appearance in
            guard let self, self.currentTheme !== appearance.presentation else { return }
            self.currentTheme = appearance.presentation
            guard let controller = self.controller, controller.isLoaded() else { return }
            controller.tableView.enumerateVisibleViews(with: { $0.updateColors() })
        }))
    }

    deinit { themeDisposable.dispose() }

    func update() { controller?.updateInputValues() }

    func select(_ identifier: InputDataIdentifier, value: InputDataValue) {
        guard let controller else { return }
        controller.proccessValidation(controller.validateData([identifier: value]))
    }
}

func regramNativeEntries(_ entries: [InputDataEntry], updated: @escaping () -> Void = {}, selected: @escaping (InputDataIdentifier, InputDataValue) -> Void = { _, _ in }, selectionStyle: RegramSelectionStyle = .multiple) -> [InputDataEntry] {
    let sourceTheme = theme
    return entries.map { entry in
        switch entry {
        case let .general(section, index, value, error, identifier, data):
            return .custom(sectionId: section, index: index, value: value, identifier: identifier, equatable: InputDataEquatable(entry), comparable: nil, item: { size, stableId in
                RegramNativeRowItem(size, stableId: stableId, data: data, error: error, selectionStyle: selectionStyle, sourceTheme: sourceTheme, fallbackAction: { selected(identifier, value) })
            })
        case let .input(section, index, value, error, identifier, mode, data, placeholder, inputPlaceholder, filter, limit):
            return .custom(sectionId: section, index: index, value: value, identifier: identifier, equatable: InputDataEquatable(entry), comparable: nil, item: { size, stableId in
                RegramNativeInputItem(size, stableId: stableId, text: value.stringValue ?? "", mode: mode, data: data, label: placeholder?.placeholder ?? "", placeholder: inputPlaceholder, error: error, limit: limit, filter: filter, updated: updated)
            })
        case let .desc(section, index, text, data) where data.viewType == .textTopItem && data.rightItem.text == nil:
            let title: String
            switch text {
            case let .plain(value): title = value
            default: return entry
            }
            return .desc(sectionId: section, index: index, text: .attributed(NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: theme.colors.grayText])), data: data)
        default:
            return entry
        }
    }
}

func RegramFormController(
    dataSignal: Signal<InputDataSignalValue, NoError>,
    title: String,
    validateData: @escaping ([InputDataIdentifier: InputDataValue]) -> InputDataValidation = { _ in .fail(.none) },
    updateDatas: @escaping ([InputDataIdentifier: InputDataValue]) -> InputDataValidation = { _ in .fail(.none) },
    afterDisappear: @escaping () -> Void = {},
    didLoad: @escaping (InputDataController, [InputDataIdentifier: InputDataValue]) -> Void = { _, _ in },
    updateDoneValue: @escaping ([InputDataIdentifier: InputDataValue]) -> ((InputDoneValue) -> Void) -> Void = { _ in { _ in } },
    removeAfterDisappear: Bool = true,
    hasDone: Bool = true,
    identifier: String = "",
    customRightButton: ((ViewController) -> BarView?)? = nil,
    beforeTransaction: @escaping (InputDataController) -> Void = { _ in },
    afterTransaction: @escaping (InputDataController) -> Void = { _ in },
    backInvocation: @escaping ([InputDataIdentifier: InputDataValue], @escaping (Bool) -> Void) -> Void = { $1(true) },
    returnKeyInvocation: @escaping (InputDataIdentifier?, NSEvent) -> InputDataReturnResult = { _, _ in .default },
    deleteKeyInvocation: @escaping (InputDataIdentifier?) -> InputDataDeleteResult = { _ in .default },
    tabKeyInvocation: @escaping (InputDataIdentifier?) -> InputDataDeleteResult = { _ in .default },
    searchKeyInvocation: @escaping () -> InputDataDeleteResult = { .default },
    getBackgroundColor: @escaping () -> NSColor = { theme.colors.listBackground },
    doneString: @escaping () -> String = { strings().navigationDone },
    isFlipped: Bool = true,
    selectionStyle: RegramSelectionStyle = .multiple
) -> InputDataController {
    let binding = RegramFormBinding()
    let signal = dataSignal |> map { value in
        InputDataSignalValue(entries: regramNativeEntries(value.entries, updated: binding.update, selected: binding.select, selectionStyle: selectionStyle), animated: value.animated, searchState: value.searchState, grouping: value.grouping, animateEverything: value.animateEverything)
    }
    let controller = InputDataController(dataSignal: signal, title: title, validateData: validateData, updateDatas: updateDatas, afterDisappear: afterDisappear, didLoad: didLoad, updateDoneValue: updateDoneValue, removeAfterDisappear: removeAfterDisappear, hasDone: hasDone, identifier: identifier, customRightButton: customRightButton, beforeTransaction: beforeTransaction, afterTransaction: afterTransaction, backInvocation: backInvocation, returnKeyInvocation: returnKeyInvocation, deleteKeyInvocation: deleteKeyInvocation, tabKeyInvocation: tabKeyInvocation, searchKeyInvocation: searchKeyInvocation, getBackgroundColor: getBackgroundColor, doneString: doneString, isFlipped: isFlipped)
    controller.preparationQueue = Queue(name: "regram.settings.form", qos: .userInitiated)
    binding.controller = controller
    binding.observeTheme()
    return controller
}
