import Foundation
import TextRecognizing
import SwiftSignalKit
import TelegramCore
import Postbox
import Translate
import TGUIKit
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import ChatModeTypes
import ChatHistoryModel
import GeneralRows
import LocalAnimations
import TelegramMediaUtils
import TelegramMedia
import AvatarUI
import MessageUtils
import InstantPageUI
import SecureIdUtils
import ColorPalette
import InAppSettings
import FoundationUtils
import ObjcUtils
import RegramCore
import RegramServices

public final class GalleryRecognition {
    private let item: MGalleryPhotoItem
    private let disposable = MetaDisposable()
    private let translateDisposable = MetaDisposable()
    private let subjectDisposable = MetaDisposable()
    private let loadedDisposable = MetaDisposable()
    private var isFullImageLoaded: Bool = false
    private var sourceIsVisible = false
    private var translationGeneration = UUID()
    private var translationIdentity: String?
    private var settingsObserver: NSObjectProtocol?
    
    public var openLink: ((String) -> Void)?
    
    private var result: AnyObject?
    private var translation: AnyObject?
    
    public let view:NSView
    public init?(_ item: MGalleryItem) {
        if let item = item as? MGalleryPhotoItem {
            if let message = item.entry.message, message.isCopyProtected() {
                return nil
            }
            self.item = item
            if #available(macOS 10.15, *) {
                self.view = TextRecognizing.ImageTextSelector(frame: .zero)
            } else {
                return nil
            }
        } else {
            return nil
        }
        if #available(macOS 10.15, *) {
            let postbox = item.context.account.postbox
            let accountId = item.context.peerId.toInt64()
            let mediaId = item.entry.mediaId
            let fullImageLoaded = item.path.get() |> take(1) |> map { _ in Void() }
            let image: Signal<TextRecognizing.Result?, TextRecognizing.Error> = combineLatest(item.image.get(), item.magnify.get(), item.appearValue, fullImageLoaded) |> castError(TextRecognizing.Error.self) |> deliverOnMainQueue |> mapToSignal { [weak self] image, magnify, visible, _ in
                self?.sourceIsVisible = magnify == 1 && visible
                self?.applyResult(nil)
                if magnify == 1, visible {
                    switch image.value {
                    case let .image(image, _):
                        if let image = image?._cgImage {
                            return TextRecognizing.recognize(image, postbox: postbox, stableId: mediaId) |> map(Optional.init) |> deliverOnMainQueue
                        } else {
                            return .single(nil)
                        }
                    default:
                        return .single(nil)
                    }
                } else {
                    return .single(nil)
                }
               
            } |> deliverOnMainQueue
            
            disposable.set(image.start(next: { [weak self] result in
                self?.applyResult(result)
            }))
            
            loadedDisposable.set((fullImageLoaded |> deliverOnMainQueue).start(next: { [weak self] in
                self?.isFullImageLoaded = true
            }))
            
            selectorView.openBarcode = { [weak self] barcode in
                self?.open(barcode)
            }
            selectorView.barcodeMenu = { [weak self] barcode in
                return self?.menu(for: barcode)
            }
            settingsObserver = NotificationCenter.default.addObserver(forName: RegramPreferences.didChange, object: nil, queue: .main) { [weak self] notification in
                guard let self, notification.object as? Int64 == accountId, let identity = self.translationIdentity,
                      RegramPreferences.shared.settings(accountId: accountId).translationIdentity != identity else { return }
                self.applyResult(self.result as? TextRecognizing.Result)
            }
        }
    }
    deinit {
        disposable.dispose()
        translateDisposable.dispose()
        subjectDisposable.dispose()
        loadedDisposable.dispose()
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }
    
    @available(macOS 10.15, *)
    private func open(_ barcode: TextRecognizing.Result.Barcode) {
        if let link = barcode.link {
            openLink?(link)
        } else {
            copy(barcode.payload)
        }
    }
    
    private func copy(_ text: String) {
        copyToClipboard(text)
        if let window = view.window as? Window {
            showModalText(for: window, text: strings().contextAlertCopied)
        }
    }
    
    @available(macOS 10.15, *)
    private func menu(for barcode: TextRecognizing.Result.Barcode) -> ContextMenu {
        let menu = ContextMenu(presentation: .current(darkPalette), betterInside: true)
        if let link = barcode.link {
            menu.addItem(ContextMenuItem(strings().chatMessageOpenLink, handler: { [weak self] in
                self?.openLink?(link)
            }, itemImage: MenuAnimation.menu_open_with.value))
            menu.addItem(ContextMenuItem(strings().textContextCopyLink, handler: { [weak self] in
                self?.copy(link)
            }, itemImage: MenuAnimation.menu_copy_link.value))
        } else {
            menu.addItem(ContextMenuItem(strings().contextCopy, handler: { [weak self] in
                self?.copy(barcode.payload)
            }, itemImage: MenuAnimation.menu_copy.value))
        }
        return menu
    }
    
    public var canLiftSubject: Bool {
        if #available(macOS 14.0, *) {
            return isFullImageLoaded
        } else {
            return false
        }
    }
    
    @available(macOS 14.0, *)
    private func liftSubject(at windowPoint: NSPoint?, completion: @escaping (TextRecognizing.Subject) -> Void) {
        let point = windowPoint.flatMap { selectorView.normalizedPoint(fromWindow: $0) }
        let signal = item.image.get()
        |> take(1)
        |> mapToSignal { value -> Signal<TextRecognizing.Subject?, NoError> in
            switch value.value {
            case let .image(image, _):
                if let image = image?._cgImage {
                    return TextRecognizing.liftSubject(image, at: point)
                }
                return .single(nil)
            default:
                return .single(nil)
            }
        }
        |> deliverOnMainQueue
        
        subjectDisposable.set(signal.start(next: { [weak self] subject in
            guard let self else {
                return
            }
            if let subject {
                self.selectorView.showLiftedSubject(subject.image, rect: subject.rect, completion: {
                    completion(subject)
                })
            } else if let window = self.view.window as? Window {
                showModalText(for: window, text: strings().gallerySubjectNotFound)
            }
        }))
    }
    
    public func copySubject(at windowPoint: NSPoint?) {
        guard #available(macOS 14.0, *) else {
            return
        }
        liftSubject(at: windowPoint, completion: { [weak self] subject in
            let representation = NSBitmapImageRep(cgImage: subject.image)
            guard let png = representation.representation(using: .png, properties: [:]) else {
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            if let tiff = representation.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
            if let window = self?.view.window as? Window {
                showModalText(for: window, text: strings().contextAlertCopied)
            }
        })
    }
    
    public func sendSubjectAsSticker(at windowPoint: NSPoint?, send: @escaping (String) -> Void) {
        guard #available(macOS 14.0, *) else {
            return
        }
        liftSubject(at: windowPoint, completion: { subject in
            let signal: Signal<String?, NoError> = Signal { subscriber in
                subscriber.putNext(GalleryRecognition.writeSticker(subject))
                subscriber.putCompletion()
                return EmptyDisposable
            }
            |> runOn(.concurrentDefaultQueue())
            |> deliverOnMainQueue
            
            _ = signal.start(next: { path in
                if let path {
                    send(path)
                }
            })
        })
    }
    
    @available(macOS 14.0, *)
    private static func writeSticker(_ subject: TextRecognizing.Subject) -> String? {
        guard let data = subject.stickerData() else {
            return nil
        }
        let path = NSTemporaryDirectory() + "subject_sticker_\(arc4random64()).webp"
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            return nil
        }
        return path
    }
    @available(macOS 10.15, *)
    public func canTranslate() -> Bool {
        guard sourceIsVisible, sourcePermitsTranslation, let result = result as? TextRecognizing.Result else {
            return false
        }
        
        switch result {
        case let .finish(_, text, _):
            let text = text.map { $0.text }.joined(separator: "\n")
            guard RegramImageTranslationBudget.hasText(text) else { return false }
            let fromLang = Translate.detectLanguage(for: text)
            let toLang = item.context.sharedContext.baseSettings.doNotTranslate.union([appAppearance.languageCode])
            
            if fromLang == nil || !toLang.contains(fromLang!) {
                return true
            }
        default:
            break
        }
        
        return false
        
    }
    
    @available(macOS 10.15, *)
    public func toggleTranslate(to: String) {
        guard let result = result as? TextRecognizing.Result else { return }
        guard translation == nil else { applyResult(result); return }
        guard sourceIsVisible, sourcePermitsTranslation, case let .finish(image, text, _) = result,
              text.contains(where: { RegramImageTranslationBudget.hasText($0.text) }) else { return }
        let toLang = RegramChatLanguagePolicy.targetCode(to)
        guard !toLang.isEmpty else { return }
        let context = item.context
        let accountId = context.peerId.toInt64()
        let settings = RegramPreferences.shared.settings(accountId: accountId)
        let identity = settings.translationIdentity
        let generation = UUID()
        translationGeneration = generation
        translationIdentity = identity
        let holder = MetaDisposable()
        translateDisposable.set(holder)
        applyResult(result, translate: .progress(result))
        let permission: () -> Signal<Bool, NoError> = { [weak self] in
            self?.translationPermission(generation: generation, identity: identity) ?? .single(false)
        }
        let signal = regramTranslateImageRegions(text.map { $0.text }, to: toLang, accountId: accountId, settings: settings, permitsTranslation: permission, telegramTranslate: { text, target in
            context.engine.messages.translate(text: text, toLang: target)
            |> mapError { _ in TranslateFetchError.network }
            |> mapToSignal { value in value.map { .single($0.0) } ?? .fail(.network) }
        })
        |> mapToSignal { translated in
            permission() |> castError(RegramImageTranslationError.self) |> mapToSignal { allowed in allowed ? .single(translated) : .fail(.outdated) }
        }
        |> deliverOnMainQueue
        var receivedResult = false
        holder.set(signal.startStrict(next: { [weak self] translated in
            receivedResult = true
            guard let self, self.translationIsCurrent(generation: generation, identity: identity) else { return }
            guard translated.count == text.count else {
                self.applyResult(result)
                self.showTranslationFailure(.failed)
                return
            }
            var values: [TextRecognizing.TranslateResult.Value] = []
            var originals: [TextRecognizing.Result.Detected] = []
            for (original, translation) in zip(text, translated) where original.text != translation {
                values.append(.init(text: translation, detected: original))
                originals.append(original)
            }
            if values.isEmpty { self.applyResult(result) }
            else { self.applyResult(result, translate: .success(translated: values, original: .finish(image: image, text: originals, barcodes: []))) }
        }, error: { [weak self] error in
            guard let self, self.translationGeneration == generation else { return }
            let current = self.translationIsCurrent(generation: generation, identity: identity)
            self.applyResult(result)
            if current, error != .outdated { self.showTranslationFailure(error) }
        }, completed: { [weak self] in
            guard !receivedResult, let self, self.translationGeneration == generation else { return }
            let current = self.translationIsCurrent(generation: generation, identity: identity)
            self.applyResult(result)
            if current { self.showTranslationFailure(.failed) }
        }))
    }

    private var sourcePermitsTranslation: Bool {
        guard !item.entry.isProtected, !item.entry.paidMedia else { return false }
        if let message = item.entry.message {
            guard message.id.namespace == Namespaces.Message.Cloud, message.id.peerId.namespace != Namespaces.Peer.SecretChat, !message.containsSecretMedia, !message.isCopyProtected() else { return false }
        }
        return item.entry.regramCanExport(accountId: item.context.peerId.toInt64())
    }

    private func translationIsCurrent(generation: UUID, identity: String) -> Bool {
        translationGeneration == generation && translationIdentity == identity && sourceIsVisible && sourcePermitsTranslation && RegramPreferences.shared.settings(accountId: item.context.peerId.toInt64()).translationIdentity == identity
    }

    private func translationPermission(generation: UUID, identity: String) -> Signal<Bool, NoError> {
        Signal { [weak self] subscriber in
            guard let self, self.translationIsCurrent(generation: generation, identity: identity) else {
                subscriber.putNext(false)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            return (regramValidateGalleryExport(context: self.item.context, entry: self.item.entry, permitsProtectedOverride: false) |> take(1) |> deliverOnMainQueue).start(next: { [weak self] allowed in
                subscriber.putNext(allowed && self?.translationIsCurrent(generation: generation, identity: identity) == true)
            }, completed: { subscriber.putCompletion() })
        } |> runOn(.mainQueue())
    }

    private func showTranslationFailure(_ error: RegramImageTranslationError) {
        guard let window = view.window as? Window else { return }
        let text = error == .limitExceeded ? regramLocalizedString("ImageTranslation.TooLarge", languageCode: appAppearance.languageCode) : strings().errorAnError
        showModalText(for: window, text: text)
    }
    
    public func hasTranslation() -> Bool {
        return translation != nil
    }
    
    
    @available(macOS 10.15, *)
    private func applyResult(_ result: TextRecognizing.Result?, translate: TextRecognizing.TranslateResult? = nil) {
        if translate == nil {
            translationGeneration = UUID()
            translationIdentity = nil
            translateDisposable.set(nil)
        }
        self.result = result as AnyObject?
        self.translation = translate as AnyObject?
        
        self.selectorView.set(result, translate: translate)
        
    }
    
    @available(macOS 10.15, *)
    private var selectorView: TextRecognizing.ImageTextSelector {
        return self.view as! TextRecognizing.ImageTextSelector
    }
    
    public var hasRecognition: Bool {
        if #available(macOS 10.15, *) {
            return self.selectorView.result != nil
        } else {
            return false
        }
       
    }
    public var hasSelectedText: Bool {
        if #available(macOS 10.15, *) {
            return self.selectorView.hasSelectedText
        } else {
            return false
        }
    }
    public func cancelSelection() {
        if #available(macOS 10.15, *) {
            self.selectorView.cancelSelection()
        }
    }
    
    public func copySelectedText() -> Bool {
        if #available(macOS 10.15, *) {
            return self.selectorView.copySelectedText()
        } else {
            return false
        }
    }
    public var selectedText: String? {
        if #available(macOS 10.15, *) {
            return self.selectorView.selectedText
        } else {
            return nil
        }
    }
}
