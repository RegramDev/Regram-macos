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
            .general(sectionId: section, index: index, value: .none, error: nil, identifier: identifier, data: .init(name: title, color: foregroundColor, icon: icon, type: type, viewType: viewType, enabled: enabled, description: description, action: action, nameAttributed: attributed))
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
}
