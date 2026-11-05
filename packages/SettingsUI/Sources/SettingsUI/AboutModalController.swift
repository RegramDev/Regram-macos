import Cocoa
import TGUIKit
import Localization
import TelegramTheme
import TelegramUtils
import RegramCore

public var APP_VERSION_STRING: String {
    var vText = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "1").\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "0")"
    
    
    #if STABLE
    vText += " Stable"
    #elseif APP_STORE
    vText += " AppStore"
    #elseif ALPHA
    vText += " Alpha"
    #else
    vText += " Beta"
    #endif
    return vText
}

fileprivate class AboutModalView : Control {
    fileprivate let copyright:TextView = TextView()
    fileprivate let descView:TextView = TextView()
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        
        
        let attribution = String(format: regramLocalizedString("About.Attribution", languageCode: appCurrentLanguage.primaryLanguage.languageCode), formatter.string(from: Date()))
        let copyrightLayout = TextViewLayout(.initialize(string: attribution, color: theme.colors.grayText, font: .normal(.small)), alignment: .center)
        copyrightLayout.measure(width:frameRect.width - 40)
        
        
        let vText = APP_VERSION_STRING

        let attr = NSMutableAttributedString()
        
        _ = attr.append(string: "Regram", color: theme.colors.text, font: .medium(.header))
        _ = attr.append(string: "\n\(vText)", color: theme.colors.link, font: .medium(.text))
        
        attr.addAttribute(.link, value: "copy", range: attr.range)

        _ = attr.append(string: "\n\n")
        
        

        _ = attr.append(string: regramLocalizedString("About.Description", languageCode: appCurrentLanguage.primaryLanguage.languageCode), color: theme.colors.text, font: .normal(.text))
        
        let descLayout = TextViewLayout(attr, alignment: .center)
        descLayout.measure(width:frameRect.width - 40)
        

        descLayout.interactions.copy = {
            copyToClipboard(APP_VERSION_STRING)
            return true
        }
        
        descLayout.interactions.processURL = { _ in
            var bp:Int = 0
            bp += 1
        }
        
        copyright.update(copyrightLayout)
        descView.update(descLayout)
        copyright.backgroundColor = theme.colors.background
        descView.backgroundColor = theme.colors.background
        addSubview(copyright)
        addSubview(descView)
        
        
 
        
        descView.isSelectable = false
        copyright.isSelectable = false
    }
    
    fileprivate override func layout() {
        super.layout()
        descView.centerX(y: 20)
        copyright.centerX(y:frame.height - copyright.frame.height - 20)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public class AboutModalController: ModalViewController {

    
    public override func viewClass() -> AnyClass {
        return AboutModalView.self
    }
    
    public override init() {
        super.init(frame: NSMakeRect(0, 0, 300, 190))
        bar = .init(height: 0)
    }
    
    public override func close(animationType: ModalAnimationCloseBehaviour = .common) {
        super.close(animationType: animationType)
    }
    
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        genericView.descView.textLayout?.interactions.processURL = { [weak self] url in
            if let url = url as? AboutInAppLink {
                SettingsHooks.shared.executeInAppLink(url)
            } else if let url = url as? String, url == "copy" {
                copyToClipboard(APP_VERSION_STRING)
                if let window = self?.window {
                    showModalText(for: window, text: strings().shareLinkCopied)
                }
                return
            }
            self?.close()
        }
        readyOnce()
    }
    
    private var genericView:AboutModalView {
        return self.view as! AboutModalView
    }
    
}
