import Cocoa
import WebKit
import TGUIKit
import TelegramTheme

final class RegramWebTranslationView: View {
    let webView: WKWebView
    let translate = NSButton(title: "", target: nil, action: nil)
    let restore = NSButton(title: "", target: nil, action: nil)
    let status = NSTextField(labelWithString: "")
    let notice = NSTextField(wrappingLabelWithString: "")

    required init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frameRect)
        addSubview(webView)
        for button in [translate, restore] { button.bezelStyle = .rounded; addSubview(button) }
        status.lineBreakMode = .byTruncatingMiddle
        addSubview(status)
        notice.font = .systemFont(ofSize: 12)
        addSubview(notice)
        updateTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateTheme() {
        appearance = theme.appearance
        backgroundColor = theme.colors.background
        status.textColor = theme.colors.text
        notice.textColor = theme.colors.grayText
        notice.stringValue = regramString("webTranslation.notice")
        restore.title = regramString("webTranslation.restore")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = max(1, bounds.width - 32)
        let translateWidth = min(width, max(80, translate.intrinsicContentSize.width))
        let restoreWidth = min(width, max(80, restore.intrinsicContentSize.width))
        translate.frame = NSRect(x: 16, y: 10, width: translateWidth, height: 28)
        let stacked = translateWidth + restoreWidth + 8 > width
        restore.frame = NSRect(x: stacked ? 16 : translate.frame.maxX + 8, y: stacked ? 44 : 10, width: restoreWidth, height: 28)
        let inlineStatus = !stacked && width - restore.frame.maxX >= 160
        status.frame = inlineStatus ? NSRect(x: restore.frame.maxX + 12, y: 15, width: max(0, bounds.width - restore.frame.maxX - 28), height: 20) : NSRect(x: 16, y: restore.frame.maxY + 8, width: width, height: 20)
        status.toolTip = status.stringValue
        let noticeTop = max(restore.frame.maxY, status.frame.maxY) + 10
        let noticeHeight = regramNativeTextHeight(notice.attributedStringValue, width: width)
        notice.frame = NSRect(x: 16, y: noticeTop, width: width, height: noticeHeight)
        let webTop = notice.frame.maxY + 12
        webView.frame = NSRect(x: 0, y: webTop, width: bounds.width, height: max(0, bounds.height - webTop))
    }
}

