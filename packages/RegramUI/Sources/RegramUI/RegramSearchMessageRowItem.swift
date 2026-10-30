import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme
import InputDataUI

func regramSearchMessageRowItem(_ size: NSSize, stableId: AnyHashable, title: String, date: String, preview: String, query: String, footer: String = "", selection: Bool? = nil, viewType: GeneralViewType, action: @escaping () -> Void, menu: @escaping () -> [ContextMenuItem]) -> GeneralRowItem {
    let type: GeneralInteractedType = selection.map(GeneralInteractedType.selectable) ?? .none
    let body = NSMutableAttributedString(attributedString: .initialize(string: date, color: theme.colors.grayText, font: .normal(.small)))
    if !footer.isEmpty {
        let tags = footer.count > 32 ? String(footer.prefix(31)) + "…" : footer
        body.append(.initialize(string: " · " + tags, color: theme.colors.accent, font: .normal(.small)))
    }
    body.append(.initialize(string: "\n", color: theme.colors.grayText, font: .normal(.small)))
    let previewOffset = body.length
    body.append(.initialize(string: preview, color: theme.colors.text, font: .normal(.text)))
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty {
        let text = preview as NSString
        var range = NSRange(location: 0, length: text.length)
        while range.length > 0 {
            let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], range: range)
            guard match.location != NSNotFound, match.length > 0 else { break }
            body.addAttribute(.foregroundColor, value: theme.colors.accent, range: NSRange(location: previewOffset + match.location, length: match.length))
            range = NSRange(location: NSMaxRange(match), length: text.length - NSMaxRange(match))
        }
    }
    return RegramNativeRowItem(size, stableId: stableId, data: .init(name: title, color: theme.colors.text, type: selection == nil ? .next : type, viewType: viewType, description: body.string, action: action, menuItems: menu), detail: body, maximumDetailLines: 5)
}
