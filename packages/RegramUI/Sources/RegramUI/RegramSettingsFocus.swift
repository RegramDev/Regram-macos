import Cocoa
import TGUIKit
import InputDataUI

func regramFocusSettings(_ controller: InputDataController, page: String?, item: String?) {
    guard let item, !item.isEmpty else { return }
    var completed = false
    let previous = controller.afterTransaction
    controller.afterTransaction = { controller in
        previous(controller)
        guard !completed else { return }
        controller.tableView.enumerateItems { row in
            guard let stable = row.stableId.base as? InputDataEntryId, let identifier = stable.identifier else { return true }
            let suffix = "." + item
            let matches = identifier.identifier == (page.map { $0 + suffix } ?? "") || identifier.identifier.hasSuffix(suffix)
            guard matches else { return true }
            completed = true
            controller.tableView.scroll(to: .center(id: row.stableId, innerId: nil, animated: true, focus: .init(focus: true), inset: 0), inset: NSEdgeInsets(), toVisible: true)
            return false
        }
    }
}
