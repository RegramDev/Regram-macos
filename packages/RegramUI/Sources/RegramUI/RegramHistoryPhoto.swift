import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme
import InputDataUI
import SwiftSignalKit
import TelegramContext

final class RegramHistoryPhotoRowItem: GeneralRowItem {
    let image: NSImage
    let concealed: Bool
    let zoomable: Bool
    let photoAction: () -> Void

    init(_ size: NSSize, stableId: AnyHashable, image: NSImage, concealed: Bool, zoomable: Bool = false, action: @escaping () -> Void) {
        self.image = image
        self.concealed = concealed
        self.zoomable = zoomable
        self.photoAction = action
        super.init(size, height: zoomable ? max(400, size.height - 80) : 280, stableId: stableId, viewType: .singleItem)
    }

    override func viewClass() -> AnyClass { RegramHistoryPhotoRowView.self }
}

private final class RegramHistoryPhotoRowView: GeneralContainableRowView {
    private let scroll = NSScrollView()
    private let imageView = NSImageView()
    private let cover = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")
    private var click: NSClickGestureRecognizer?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = imageView
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(scroll)
        cover.material = .hudWindow
        cover.blendingMode = .withinWindow
        cover.state = .active
        addSubview(cover)
        label.alignment = .center
        label.isSelectable = false
        cover.addSubview(label)
        cover.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? RegramHistoryPhotoRowItem else { return }
        imageView.image = item.image
        scroll.allowsMagnification = item.zoomable
        scroll.minMagnification = 1
        scroll.maxMagnification = 5
        scroll.magnification = 1
        cover.isHidden = !item.concealed
        label.stringValue = regramString("EditHistory.RevealPhoto")
        label.textColor = theme.colors.text
        scroll.setAccessibilityLabel(regramString(item.concealed ? "EditHistory.RevealPhoto" : "EditHistory.ViewPhoto"))
        if let click { scroll.removeGestureRecognizer(click) }
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        recognizer.numberOfClicksRequired = item.zoomable ? 2 : 1
        scroll.addGestureRecognizer(recognizer)
        click = recognizer
        needsLayout = true
    }

    @objc private func clicked() {
        guard let item = item as? RegramHistoryPhotoRowItem else { return }
        if item.zoomable { scroll.setMagnification(scroll.magnification > 1 ? 1 : 2, centeredAt: NSPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)) }
        else { item.photoAction() }
    }

    override func layout() {
        super.layout()
        scroll.frame = containerView.bounds.insetBy(dx: 10, dy: 6)
        imageView.frame = NSRect(origin: .zero, size: scroll.contentSize)
        cover.frame = scroll.frame
        label.frame = NSRect(x: 10, y: max(0, (cover.bounds.height - 22) / 2), width: max(0, cover.bounds.width - 20), height: 22)
    }
}

func regramHistoryImageController(context: any AccountContextProtocol, image: NSImage) -> InputDataController {
    let rows: [InputDataEntry] = [
        .sectionId(0, type: .normal),
        .custom(sectionId: 1, index: 0, value: .none, identifier: InputDataIdentifier("history_image_detail"), equatable: InputDataEquatable(image.size), comparable: nil, item: { size, stableId in
            RegramHistoryPhotoRowItem(size, stableId: stableId, image: image, concealed: false, zoomable: true, action: {})
        })
    ]
    return InputDataController(dataSignal: .single(InputDataSignalValue(entries: rows)), title: regramString("EditHistory.ViewPhoto"), removeAfterDisappear: false, hasDone: false)
}
