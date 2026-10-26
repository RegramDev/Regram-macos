import ChatHistoryModel
import RegramCore
import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import InputDataUI

private final class CenterView : TitledBarView {
    let segment: CatalinaStyledSegmentController
    var select:((Int)->Void)? = nil
    init(controller: ViewController) {
        self.segment = CatalinaStyledSegmentController(frame: NSMakeRect(0, 0, 240, 30))
        super.init(controller: controller)
        self.segment.fitContent = true
        self.segment.fitContentHorizontalPadding = 32

        segment.add(segment: .init(title: strings().selectColorTabProfile, handler: { [weak self] in
            self?.select?(0)
        }))

        segment.add(segment: .init(title: strings().selectColorTabName, handler: { [weak self] in
            self?.select?(1)
        }))

        self.addSubview(segment.view)

        updateLocalizationAndTheme(theme: theme)
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)

        segment.theme = CatalinaSegmentTheme(backgroundColor: theme.colors.listBackground, foregroundColor: theme.colors.background, activeTextColor: theme.colors.text, inactiveTextColor: theme.colors.listGrayText)

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let intrinsic = segment.intrinsicContentWidth
        let available = max(0, frame.width - 60)
        // 180pt minimum so a two-item segment doesn't look like a tiny chip;
        // capped at `frame.width - 60` so the 30pt-per-side margin from the
        // surrounding chrome is preserved on narrow windows.
        let target = max(180, intrinsic)
        let width = min(target, available)
        let height: CGFloat = 30
        let x = floorToScreenPixels(backingScaleFactor, (frame.width - width) / 2)
        let y = floorToScreenPixels(backingScaleFactor, (frame.height - height) / 2)
        segment.view.frame = NSRect(x: x, y: y, width: width, height: height)
    }
}



public final class SelectColorParentController : SectionViewController {
    fileprivate let peer: Peer
    fileprivate let callback: SelectColorCallback?
    fileprivate let profileController: InputDataController
    fileprivate let nameController: InputDataController
    fileprivate let context: any AccountContextProtocol
    
    fileprivate let profileData = SelectColorControllerCollectData()
    fileprivate let nameData = SelectColorControllerCollectData()
    private let saveAction = SelectColorSaveAction()
    
    public init(_ context: any AccountContextProtocol, peer: Peer, callback: SelectColorCallback? = nil) {
        self.peer = peer
        self.callback = callback
        self.context = context
        
        

        self.profileController = SelectColorController(context: context, peer: peer, callback: callback, destination: .profile, dataCollector: profileData)
        self.nameController = SelectColorController(context: context, peer: peer, callback: callback, destination: .name, dataCollector: nameData)
        var items:[SectionControllerItem] = []
        items.append(SectionControllerItem(title: { "" }, controller: profileController))
        items.append(SectionControllerItem(title: { "" }, controller: nameController))
        super.init(sections: items, selected: 0, hasBar: true)
        for controller in [self.profileController, self.nameController] {
            let willAppear = controller.willAppear
            controller.willAppear = { [weak self] controller in
                self?.saveAction.setActive(true)
                willAppear?(controller)
            }
            let didAppear = controller.didAppear
            controller.didAppear = { [weak self] controller in
                self?.saveAction.setActive(true)
                didAppear?(controller)
            }
            let willDisappear = controller.willDisappear
            controller.willDisappear = { [weak self] controller in
                self?.saveAction.setActive(false)
                willDisappear?(controller)
            }
        }


    }
    
    public override func getCenterBarViewOnce() -> TitledBarView {
        return CenterView(controller: self)
    }
    
    
    public override var enableBack: Bool {
        return true
    }
    
    public override var supportSwipes: Bool {
        return self.selectedIndex == 0
    }
    
    public override func getRightBarViewOnce() -> BarView {
        return TextButtonBarView(controller: self, text: strings().modalApply, style: navigationButtonStyle)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        centerView.select = { [weak self] index in
            self?.select(index, true)
        }
        
        self.selectionUpdateHandler = { [weak self] index in
            self?.centerView.segment.set(selected: index, animated: true)
        }
        
        rightBarView.set(handler: { [weak self] _ in
            self?.collectAndInvoke()
        }, for: .Click)
    }
    
    private func collectAndInvoke() {
        guard self.saveAction.isActive, !self.saveAction.isPending, self.isLoaded(), let window = self.view.window as? Window else { return }
        guard self.peer.id == self.context.peerId, self.peer is TelegramUser else { return }
        let profileData = self.profileData.getData()
        let nameData = self.nameData.getData()
        
        if case .peerId(peer.id) = nameData?.selected_Gift?.owner {
            var bp = 0
            bp += 1
        } else if let unique = nameData?.selected_Gift {
            self.nameData.buyAndApply(unique)
            return
        }
        
        if let profileData, let nameData {
            let nameColor = nameData.selected ?? nameData.peer.nameColor ?? .preset(.blue)
            let backgroundEmojiId = nameData.backgroundEmojiId
            let profileColor = profileData.selected_profile
            let profileBackgroundEmojiId = profileData.backgroundEmojiId_profile
            if regramLocalGiftsEnabled(context: context) {
                if regramSaveLocalGiftAppearance(context: context, nameColor: nameColor, profileColor: profileColor?.nameColor, replyFileId: backgroundEmojiId, backgroundFileId: profileBackgroundEmojiId, emojiStatus: profileData.emojiStatus) { self.executeReturn() }
                return
            }
            guard (profileData.emojiStatus?.fileId ?? 0) >= 0, !regramIsLocalGiftAppearance(nameColor: nameColor, emojiStatus: profileData.emojiStatus), (backgroundEmojiId ?? 0) >= 0, (profileBackgroundEmojiId ?? 0) >= 0, profileData.emojiStatusGift.map({ !regramIsLocalGift(.unique($0)) }) ?? true else { self.executeReturn(); return }
            var signals:[Signal<Never, SelectColorSaveError>] = []
            signals.append(SelectColorStatusUpdate.request(context: context, peer: profileData.peer, status: profileData.emojiStatus, gift: profileData.emojiStatusGift))
            signals.append(context.engine.accountData.updateNameColorAndEmoji(nameColor: nameColor.getUpdate(backgroundEmojiId), profileColor: profileColor?.nameColor, profileBackgroundEmojiId: profileBackgroundEmojiId) |> ignoreValues |> mapError { _ in SelectColorSaveError.generic })
            self.saveAction.perform(signal: combineLatest(signals) |> ignoreValues, window: window, canPresent: { [weak self, weak window] in
                guard let self, let window else { return false }
                return self.isLoaded() && self.view.window === window
            }, failed: { [weak window] in
                if let window { showModalText(for: window, text: strings().unknownError) }
            }, completed: { [weak self] in
                self?.executeReturn()
            })
        }
        
    }
    
    
    public override func returnKeyAction() -> KeyHandlerResult {
        collectAndInvoke()
        return .invoked
    }
    
    private var centerView: CenterView {
        return self.centerBarView as! CenterView
    }
    
}
