import Cocoa
import CoreMedia
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramMedia
import TGUIKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import InlineMediaGrid
import FetchManager


public class ChatMediaContentView: Control, NSDraggingSource, NSPasteboardItemDataProvider, PinchableView {

    
    
    
    private var acceptDragging:Bool = false
    private var inDragging:Bool = false
    private var mouseDownPoint: NSPoint = NSZeroPoint
    public var parent:Message?
    public var media:Media?
    public var context:(any AccountContextProtocol)?
    public var parameters:ChatMediaLayoutParameters?
    public private(set) var fetchControls:FetchControls!
    public var fetchStatus: MediaResourceStatus? {
        didSet {
            let owner = self.fetchStatusOwnerKey
            self.statusChangeIsAnimatable = oldValue != nil && self.fetchStatusOwner == owner && mediaStatusKind(oldValue) != mediaStatusKind(self.fetchStatus)
            self.fetchStatusOwner = owner
        }
    }
    private var fetchStatusOwner: AnyHashable?
    public private(set) var statusChangeIsAnimatable: Bool = false
    public var hasFetchStatusForCurrentMedia: Bool {
        return self.fetchStatus != nil && self.fetchStatusOwner == self.fetchStatusOwnerKey
    }
    private var fetchStatusOwnerKey: AnyHashable? {
        if let parent = self.parent {
            return AnyHashable(parent.stableId)
        }
        return self.media?.id.map { AnyHashable($0) }
    }
    public var dragDisposable:MetaDisposable = MetaDisposable()
    public var positionFlags: LayoutPositionFlags?
    
    public var invokeNextMouse: Bool = false 
    
    public override var backgroundColor: NSColor {
        get {
            return super.backgroundColor
        }
        set {
            super.backgroundColor = newValue
            for view in subviews {
                if !(view is TransformImageView) && !(view is SelectingControl) && !(view is GIFPlayerView) && !(view is ChatMessageAccessoryView) && !(view is ChatMediaEditControl) && !(view is ProgressIndicator) && !(view is VoiceTranscriptionControl) {
                    if let view = view as? View, view.isDynamicColorUpdateLocked {
                        continue
                    }
                    view.background = newValue
                }
            }
        }
    }
    
    public weak var table:TableView?
    
    
    public override init() {
        super.init()
        fetchControls = FetchControls(fetch: { [weak self] in
            self?.executeInteraction(true)
            self?.open()
        })
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        fetchControls = FetchControls(fetch: { [weak self] in
            self?.executeInteraction(true)
        })
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func playIfNeeded(_ playSound: Bool = false) {
        
    }
    
    public func willRemove() -> Void {
        //self.cancel()
    }
    
    public func clean() -> Void {
        
    }
    
    public func cancel() -> Void {
        
    }
    
    public func delete() -> Void {
        cancel()
        let engine = context?.engine.messages
        if let parentId = parent?.id {
            _ = context?.account.postbox.transaction({ transaction -> Void in
                engine?.deleteMessages(transaction: transaction, ids: [parentId])
            }).start()
        }
    }
    
    public override var allowsVibrancy: Bool {
        return true
    }
    
    public func cancelFetching() {
        if let context = context, let media = media {
            if let parent, let image = media as? TelegramMediaImage, let representation = image.representationForDisplayAtSize(.init(width: 1280, height: 1280)) {
                context.fetchManager.cancelInteractiveFetches(category: .image, location: .chat(parent.id.peerId), locationKey: .messageId(parent.id), resource: representation.resource)
            }
            if let parent = parent, let parameters = parameters {
                parameters.cancelOperation(parent, media)
            } else {
                if let media = media as? TelegramMediaFile {
                    cancelFreeMediaFileInteractiveFetch(context: context, resource: media.resource)
                } else if let media = media as? TelegramMediaImage {
                    chatMessagePhotoCancelInteractiveFetch(account: context.account, photo: media)
                }
            }
        }
    }
    
    public func open() -> Void {
        
    }
    
    public func fetch(userInitiated: Bool) -> Void {
        
    }
    
    public func preloadStreamblePart() {
        
    }
    
    public func updateMouse() {
        
    }
    
    public func executeInteraction(_ isControl:Bool) -> Void {
        if let fetchStatus = self.fetchStatus, userInteractionEnabled {
            switch fetchStatus {
            case .Fetching, .Paused:
                if isControl {
                    if let parent = parent, parent.flags.contains(.Unsent) && !parent.flags.contains(.Failed) {
                        delete()
                    }
                    cancelFetching()
                } else {
                }
            case .Remote:
                fetch(userInitiated: true)
            case .Local:
                open()
                break
            }
        }
    }
    
    public func previewMediaIfPossible() -> Bool {
        return false
    }
    
    deinit {
        self.clean()
        dragDisposable.dispose()
    }
     
     public func update(size: NSSize) {
         
     }
    
    public func update(with media: Media, size:NSSize, context:any AccountContextProtocol, parent:Message?, table:TableView?, parameters:ChatMediaLayoutParameters? = nil, animated: Bool = false, positionFlags: LayoutPositionFlags? = nil, approximateSynchronousValue: Bool = false) -> Void  {
        self.setContent(size: size, animated: animated)
        self.parameters = parameters
        self.positionFlags = positionFlags
        self.context = context
        self.parent = parent
        self.table = table
                
        self.media = media
        
        if let parameters = parameters {
            if let parent = parent {
                if parameters.automaticDownloadFunc(parent) {
                    fetch(userInitiated: false)
                    preloadStreamblePart()
                } else {
                    if parameters.preload {
                        preloadStreamblePart()
                    }
                }
            } else if parameters.automaticDownload {
                fetch(userInitiated: false)
                preloadStreamblePart()
            } else if parameters.preload {
                preloadStreamblePart()
            }
            
        }
        
    }
    
    public var autoDownload: Bool {
        if let parameters = parameters {
            if let parent = parent {
                if parameters.automaticDownloadFunc(parent) {
                   return true
                }
            } else if parameters.automaticDownload {
               return true
            }
        }
        return false
    }
    
    public func addSublayer(_ layer:CALayer) -> Void {
        self.layer?.addSublayer(layer)
    }
    
    public func setContent(size:NSSize, animated: Bool) -> Void {
        let frame = NSMakeRect(NSMinX(self.frame), NSMinY(self.frame), size.width, size.height)
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        transition.updateFrame(view: self, frame: frame)
    }
    
    public override func copy() -> Any {
        let view = View()
        view.frame = self.frame
        return view
    }
    
    public func interactionContentView(for innerId: AnyHashable, animateIn: Bool ) -> NSView {
        return self
    }
    
    public func interactionControllerDidFinishAnimation(interactive: Bool) {
        
    }
    
    public func videoTimebase() -> CMTimebase? {
        return nil
    }
    public func applyTimebase(timebase: CMTimebase?) {
        
    }
    
    public func addAccesoryOnCopiedView(view: NSView) {

    }
    
    public func draggingAbility(_ event:NSEvent) -> Bool {
        if let superview = superview {
            return NSPointInRect(superview.convert(event.locationInWindow, from: nil), frame)
        }
        return false
    }
    
    public override func mouseDown(with event: NSEvent) {
        
        if event.modifierFlags.contains(.control) {
            super.mouseDown(with: event)
            return
        }
        
        if userInteractionEnabled {
            inDragging = false
            dragpath = nil
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            acceptDragging = draggingAbility(event) && parent != nil && !parent!.containsSecretMedia && !parent!.isCopyProtected()
            
            if let parent = parent, parent.id.peerId.namespace == Namespaces.Peer.SecretChat {
                acceptDragging = false
            }
            if hasHandlers || invokeNextMouse {
                super.mouseDown(with: event)
            }
        }
        
        if !acceptDragging {
            super.superview?.mouseDown(with: event)
        }
    }
    
    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            return .copy
        case .withinApplication:
            return []
        @unknown default:
            return []
        }
    }
    private var dragpath:String? = nil
    
    public func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if let dragpath = dragpath {
            pasteboard?.clearContents()
            pasteboard?.declareTypes([.kFilenames, .string], owner: self)
            pasteboard?.setPropertyList([dragpath], forType: .kFilenames)
            pasteboard?.setString(dragpath, forType: .string)
        }
    }
    
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: frame.size, transition: .immediate)
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
    }
    
    
    public override func mouseDragged(with event: NSEvent) {
        if self.fetchStatus == .Local {
            if !inDragging && acceptDragging {
                let current = convert(event.locationInWindow, from: nil)
                guard abs(mouseDownPoint.x - current.x) > 10 || abs(mouseDownPoint.y - current.y) > 10 else {
                    return
                }
                
                if let context = context, let resource = mediaResource(from: media), let mimeType = mediaResourceMIMEType(from: media) {
                    let result = context.account.postbox.mediaBox.resourceData(resource) |> mapToSignal { [weak media] resource -> Signal<String?, NoError> in
                        if resource.complete {
                            return resourceType( mimeType: mimeType) |> mapToSignal { [weak media] ext -> Signal<String?, NoError> in
                                return putFileToTemp(from: resource.path, named:  mediaResourceName(from: media, ext: ext))
                            }
                        } else {
                            return .single(nil)
                        }
                        
                        } |> deliverOnMainQueue
                    
                    dragDisposable.set(result.start(next: { [weak self] path in
                        if let strongSelf = self, let path = path {
                            strongSelf.dragpath = path
                            if let cgImage = strongSelf.contents {
                                let image = NSImage(cgImage: cgImage as! CGImage, size: strongSelf.contentFrame.size)
                                
                                let writer = NSPasteboardItem()
                                
                                writer.setDataProvider(strongSelf, forTypes: [.kFileUrl])
                                let item = NSDraggingItem( pasteboardWriter: writer )
                                item.setDraggingFrame(strongSelf.contentFrame, contents: image)
                                strongSelf.beginDraggingSession(with: [item], event: event, source: strongSelf)
                                
                            }
                            strongSelf.inDragging = true
                        }
                    }))
                    
                } else {
                    super.mouseDragged(with: event)
                }
                
            } else {
                super.superview?.mouseDragged(with: event)
            }
            
        } else {
            super.mouseDragged(with: event)
        }
        
    }
    
    public var canSpamClicks: Bool {
        return false
    }
    
    public override func mouseUp(with event: NSEvent) {
            
        if event.modifierFlags.contains(.control) {
            super.mouseUp(with: event)
            return
        }
        
        if userInteractionEnabled, hasHandlers || invokeNextMouse {
            super.mouseUp(with: event)
        }
        if !inDragging && draggingAbility(event) && mouseInside() && userInteractionEnabled, event.clickCount <= 1 || canSpamClicks {
            executeInteraction(false)
        } else {
            super.superview?.mouseUp(with: event)
        }
        dragpath = nil
        dragDisposable.set(nil)
        inDragging = false
        acceptDragging = false
    }
    
    public var contents: Any? {
        return nil
    }
    
    
    public var contentFrame: NSRect {
        return bounds
    }
    
}

private func mediaStatusKind(_ status: MediaResourceStatus?) -> Int {
    switch status {
    case .none:
        return -1
    case .Remote:
        return 0
    case .Fetching, .Paused:
        return 1
    case .Local:
        return 2
    }
}
