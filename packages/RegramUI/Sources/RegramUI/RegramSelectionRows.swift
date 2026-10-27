import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme
import InputDataUI

func regramSegmentedRowItem(_ size: NSSize, stableId: AnyHashable, labels: [String], selected: Int, changed: @escaping (Int) -> Void) -> SegmentTypesRowItem {
    let items = labels.enumerated().map { index, title in
        ScrollableSegmentItem(title: title, index: index, uniqueId: Int64(index), selected: index == selected, insets: NSEdgeInsets(left: 10, right: 10), icon: nil, theme: ScrollableSegmentTheme.standard(theme.colors), equatable: UIEquatable(title))
    }
    return SegmentTypesRowItem(size, stableId: stableId, items: items, viewType: .singleItem, callback: { value in
        guard labels.indices.contains(Int(value)) else { return }
        changed(Int(value))
    })
}

func regramConfigureSegmentedRows(_ controller: InputDataController) {
    func configure(_ view: TableRowView, _ item: TableRowItem) {
        guard item is SegmentTypesRowItem, let view = view as? GeneralContainableRowView else { return }
        view.updateLayout(size: view.frame.size, transition: .immediate)
        view.layout()
        for segment in view.containerView.subviews.compactMap({ $0 as? ScrollableSegmentView }) {
            segment.fitToWidth = true
            segment.theme = .standard(theme.colors)
            segment.layout()
        }
    }
    let didLoad = controller.didLoad
    controller.didLoad = { controller, values in
        didLoad(controller, values)
        let afterSetupItem = controller.tableView.afterSetupItem
        controller.tableView.afterSetupItem = { view, item in
            afterSetupItem?(view, item)
            configure(view, item)
        }
        controller.tableView.enumerateViews { view in
            if let item = view.item { configure(view, item) }
            return true
        }
    }
    let afterTransaction = controller.afterTransaction
    controller.afterTransaction = { controller in
        afterTransaction(controller)
        controller.tableView.enumerateViews { view in
            if let item = view.item { configure(view, item) }
            return true
        }
    }
}

func regramSliderRowItem(_ size: NSSize, stableId: AnyHashable, title: String, value: Int, range: ClosedRange<Int>, changed: @escaping (Int) -> Void) -> PrecieSliderRowItem {
    let value = min(range.upperBound, max(range.lowerBound, value))
    let length = max(1, range.upperBound - range.lowerBound)
    return PrecieSliderRowItem(size, stableId: stableId, current: CGFloat(value - range.lowerBound) / CGFloat(length), markers: ["\(range.lowerBound)%", "\(range.upperBound)%"], showValue: title + "  \(value)%", update: { progress in
        changed(min(range.upperBound, max(range.lowerBound, range.lowerBound + Int((progress * CGFloat(length)).rounded()))))
    }, viewType: .singleItem)
}

func regramProgressRowItem(_ size: NSSize, stableId: AnyHashable, title: String, progress: Double) -> GeneralInteractedRowItem {
    let percent = Int(min(1, max(0, progress)) * 100)
    return GeneralInteractedRowItem(size, stableId: stableId, name: title, description: "\(percent)%", type: .loading, viewType: .singleItem)
}
