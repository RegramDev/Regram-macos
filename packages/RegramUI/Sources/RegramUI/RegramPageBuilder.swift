import Cocoa
import TGUIKit
import GeneralRows
import InputDataUI
import RegramCore
import TelegramTheme

private struct RegramPageElement {
    let sectionId: Int32?
    let makeEntry: (GeneralViewType) -> InputDataEntry
}

struct RegramPageBuilder {
    private var elements: [RegramPageElement] = []
    private var sectionId: Int32 = 0
    private var index: Int32 = 0
    let page: String

    init(page: String, sectionId: Int32 = 0, index: Int32 = 0) { self.page = page; self.sectionId = sectionId; self.index = index }
    var nextSectionId: Int32 { sectionId }
    var nextIndex: Int32 { index }
    var entries: [InputDataEntry] {
        elements.enumerated().map { position, element in
            guard let section = element.sectionId else { return element.makeEntry(.singleItem) }
            let previous = position > 0 && elements[position - 1].sectionId == section
            let next = position + 1 < elements.count && elements[position + 1].sectionId == section
            let viewType: GeneralViewType = previous ? (next ? .innerItem : .lastItem) : (next ? .firstItem : .singleItem)
            return element.makeEntry(viewType)
        }
    }

    private mutating func append(_ entry: InputDataEntry) {
        elements.append(RegramPageElement(sectionId: nil, makeEntry: { _ in entry }))
    }

    private mutating func appendRow(_ makeEntry: @escaping (Int32, Int32, GeneralViewType) -> InputDataEntry) {
        let section = sectionId
        let rowIndex = index
        elements.append(RegramPageElement(sectionId: section, makeEntry: { makeEntry(section, rowIndex, $0) }))
        index += 1
    }

    mutating func section(_ title: String? = nil) {
        append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        if let title { text(regramString(title), header: true) }
    }

    mutating func text(_ value: String, header: Bool = false, attributed: NSAttributedString? = nil) {
        append(.desc(sectionId: sectionId, index: index, text: attributed.map(GeneralRowTextType.attributed) ?? .plain(value), data: .init(color: theme.colors.listGrayText, viewType: header ? .textTopItem : .textBottomItem)))
        index += 1
    }

    mutating func row(_ key: String, title: String, type: GeneralInteractedType = .none, enabled: Bool = true, attributed: NSAttributedString? = nil, icon: CGImage? = nil, description: String? = nil, color: NSColor? = nil, action: (() -> Void)? = nil) {
        let identifier = InputDataIdentifier(page + "." + key)
        let defaultColor: NSColor
        switch type {
        case .none, .loading: defaultColor = action == nil ? theme.colors.text : theme.colors.accent
        default: defaultColor = theme.colors.text
        }
        let foregroundColor = color ?? defaultColor
        appendRow { section, index, viewType in
            .general(sectionId: section, index: index, value: .none, error: nil, identifier: identifier, data: .init(name: title, color: foregroundColor, icon: icon, type: type, viewType: viewType, enabled: enabled, description: description, descTextColor: theme.colors.grayText, action: action, nameAttributed: attributed))
        }
    }

    mutating func custom(_ key: String, equatable: InputDataEquatable?, item: @escaping (NSSize, InputDataEntryId) -> TableRowItem) {
        append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier(page + "." + key), equatable: equatable, comparable: nil, item: item))
        index += 1
    }

    mutating func input(_ key: String, value: String, title: String, placeholder: String? = nil, limit: Int32 = 2048, icon: CGImage? = nil) {
        let identifier = InputDataIdentifier(page + "." + key)
        let label = title.isEmpty ? icon.map { InputDataInputPlaceholder(icon: $0) } : InputDataInputPlaceholder(title, icon: icon)
        appendRow { section, index, viewType in
            .input(sectionId: section, index: index, value: .string(value), error: nil, identifier: identifier, mode: .plain, data: .init(viewType: viewType), placeholder: label, inputPlaceholder: placeholder ?? title, filter: { $0 }, limit: limit)
        }
    }

    mutating func search(_ key: String, value: String, update: @escaping (String) -> Void) {
        append(regramSearchEntry(sectionId: sectionId, index: index, value: value, identifier: InputDataIdentifier(page + "." + key), update: update))
        index += 1
    }
}

private struct RegramSearchPresentation: Equatable {
    let value: String
    let viewType: GeneralViewType
}

func regramSearchEntry(sectionId: Int32, index: Int32, value: String, identifier: InputDataIdentifier, viewType: GeneralViewType = .singleItem, update: @escaping (String) -> Void) -> InputDataEntry {
    .custom(sectionId: sectionId, index: index, value: .string(value), identifier: identifier, equatable: InputDataEquatable(RegramSearchPresentation(value: value, viewType: viewType)), comparable: nil, item: { size, stableId in
        SearchRowItem(size, stableId: stableId, searchInteractions: SearchInteractions({ state, _ in
            update(state.request)
        }, { state in
            update(state.request)
        }), viewType: viewType.withUpdatedInsets(NSEdgeInsets()))
    })
}

func regramRestoreSearchQuery(_ controller: InputDataController, identifier: InputDataIdentifier, query: @escaping () -> String) {
    let externalFirstResponder = controller._externalFirstResponder
    controller._externalFirstResponder = { [weak controller] in
        if let responder = externalFirstResponder?() { return responder }
        guard let controller, query().isEmpty else { return nil }
        if let responder = controller.window?.firstResponder as? NSView, responder !== controller.tableView.documentView, responder.isDescendant(of: controller.genericView) { return nil }
        if let view = controller.tableView.item(stableId: AnyHashable(InputDataEntryId.custom(identifier)))?.view as? SearchRowView, view.searchView.input.hasMarkedText() { return nil }
        return controller.tableView.documentView
    }
    func configure(_ view: TableRowView, item: TableRowItem) -> SearchRowView? {
        guard item.stableId == AnyHashable(InputDataEntryId.custom(identifier)), let view = view as? SearchRowView else { return nil }
        view.containerView.backgroundColor = .clear
        view.containerView.set(background: .clear, for: .Normal)
        return view
    }
    let didLoad = controller.didLoad
    controller.didLoad = { controller, values in
        didLoad(controller, values)
        let afterSetupItem = controller.tableView.afterSetupItem
        controller.tableView.afterSetupItem = { view, item in
            afterSetupItem?(view, item)
            guard let view = configure(view, item: item) else { return }
            let search = view.searchView
            let value = query()
            let window = view.window
            let responder = window?.firstResponder
            guard search.query != value, !search.input.hasMarkedText(), (responder as? NSTextView)?.hasMarkedText() != true else { return }
            let interactions = search.searchInteractions
            search.searchInteractions = nil
            search.setString(value)
            if !value.isEmpty { search.change(state: .Focus, false) }
            if let window, window.firstResponder !== responder { window.makeFirstResponder(responder) }
            search.searchInteractions = interactions
        }
    }
    let afterTransaction = controller.afterTransaction
    controller.afterTransaction = { controller in
        afterTransaction(controller)
        controller.tableView.enumerateViews { view in
            if let item = view.item { _ = configure(view, item: item) }
            return true
        }
    }
}
