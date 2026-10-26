import Cocoa
import TelegramCore

import SwiftSignalKit
import Postbox
import TGUIKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import ChatHistoryModel
import AlertsUI
import PremiumUI
import RegramCore
import RegramServices

private func regramPastedPhotoPath(_ path: String) -> String {
    let source = URL(fileURLWithPath: path)
    let target = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(RGMediaPolicy.pastedPhotoFilenamePrefix + UUID().uuidString).appendingPathExtension(source.pathExtension)
    do {
        try FileManager.default.moveItem(at: source, to: target)
        return target.path
    } catch {
        return path
    }
}

public class InputPasteboardParser: NSObject {

    
    public class func getPasteboardUrls(_ pasteboard: NSPasteboard, context: any AccountContextProtocol) -> Signal<[URL], NoError> {
        if RegramPreferences.shared.settings(accountId: context.peerId.toInt64())["clipboardOriginalImages"].bool, let original = RegramClipboardImages.snapshot(from: pasteboard), original.containsImage {
            return .single((try? RegramClipboardImages.preparingPhotos(original))?.urls.filter { fileSize($0.path).map { fileSizeLimitExceed(context: context, fileSize: $0) } ?? false } ?? [])
        }
        let items = pasteboard.pasteboardItems
        
        if let items = items, !items.isEmpty {
            var files:[URL] = []
            
            for item in items {
                let path = item.string(forType: NSPasteboard.PasteboardType(rawValue: "public.file-url"))
                if let path = path, let url = URL(string: path) {
                    files.append(url)
                }
            }
            
            var image:NSImage? = nil
            
            if files.isEmpty {
                if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], !images.isEmpty {
                    image = images[0]
                }
            }
            
            
            files = files.filter { path -> Bool in
                if let size = fileSize(path.path) {
                    let exceed = fileSizeLimitExceed(context: context, fileSize: size)
                    return exceed
                }
                return false
            }
            
            
            if !files.isEmpty {
                return .single(files)
            } else if let image = image {
                return putToTemp(image: image, compress: false) |> map { [URL(fileURLWithPath: regramPastedPhotoPath($0))] } |> deliverOnMainQueue
            }
            
        }
        
        return .single([])
    }
    
    public class func canProccessPasteboard(_ pasteboard:NSPasteboard, context: any AccountContextProtocol) -> Bool {
        let items = pasteboard.pasteboardItems
        
        if let items = items, !items.isEmpty {
            var files:[URL] = []
            
            for item in items {
                let path = item.string(forType: NSPasteboard.PasteboardType(rawValue: "public.file-url"))
                if let path = path, let url = URL(string: path) {
                    files.append(url)
                }
                
            }
            
            var image:NSImage? = nil
            
            if files.isEmpty {
                if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], !images.isEmpty {
                    image = images[0]
                }
            }
            
            
            if let _ = items[0].types.firstIndex(of: NSPasteboard.PasteboardType(rawValue: "com.apple.traditional-mac-plain-text")) {
                return true
            }
            
            let previous = files.count
            
            files = files.filter { path -> Bool in
                if let size = fileSize(path.path) {
                    let exceed = fileSizeLimitExceed(context: context, fileSize: size)
                    return exceed
                }
                return false
            }
            
            let afterSizeCheck = files.count
            
            if afterSizeCheck == 0 && previous != afterSizeCheck {
                return false
            }
            
            if !files.isEmpty {
                
                return false
            } else if let _ = image {
                return false
            }
            
        }
        
        return true
    }
    
    public class func proccess(pasteboard:NSPasteboard, chatInteraction:ChatInteraction, window:Window) -> Bool {
        let originalImages = RegramPreferences.shared.settings(accountId: chatInteraction.interactionContext.peerId.toInt64())["clipboardOriginalImages"].bool
        if originalImages, let original = RegramClipboardImages.snapshot(from: pasteboard), original.containsImage {
            let valid = original.urls.filter { fileSize($0.path).map { fileSizeLimitExceed(context: chatInteraction.interactionContext, fileSize: $0) } ?? false }
            guard valid.count == original.urls.count else { showFileLimit(context: chatInteraction.interactionContext, fileSize: nil); return false }
            if let peer = chatInteraction.presentation.peer, let text = permissionText(from: peer, for: .banSendMedia) { alert(for: window, info: text); return false }
            guard let photos = try? RegramClipboardImages.preparingPhotos(original) else { alert(for: window, info: strings().unknownError); return false }
            if valid.count == 1, chatInteraction.presentation.interfaceState.editState?.canEditMedia == true {
                let replacement = chatInteraction.beginMediaReplacement()
                _ = (Sender.generateMedia(for: MediaSenderContainer(path: photos.urls[0].path, isFile: false), account: chatInteraction.interactionContext.account, isSecretRelated: chatInteraction.peerId.namespace == Namespaces.Peer.SecretChat) |> deliverOnMainQueue).start(next: { [weak chatInteraction] media, _ in
                    chatInteraction?.applyMediaReplacement(media, request: replacement)
                })
            } else { chatInteraction.showPreviewSender(photos.urls, photos.asMedia, nil) }
            return false
        }
        let items = pasteboard.pasteboardItems
        
        
        if let items = items, !items.isEmpty {
            var files:[URL] = []
            
            for item in items {
                let path = item.string(forType: NSPasteboard.PasteboardType(rawValue: "public.file-url"))
                if let path = path, let url = URL(string: path) {
                    files.append(url)
                }
            }
            
            var image:NSImage? = nil
            
            if files.isEmpty {
                                                
                if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], !images.isEmpty {
                    
                    if let representation = images[0].representations.first as? NSPDFImageRep {
                        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "ios_scan_\(arc4random()).pdf")
                        
                        try? representation.pdfRepresentation.write(to: url)
                        
                        files.append(url)
                        image = nil
                    } else {
                        image = images[0]
                    }
                }
            }
            
            if let _ = items[0].types.firstIndex(of: NSPasteboard.PasteboardType(rawValue: "com.microsoft.appbundleid")) {
                return true
            }
            
            let previous = files.count
            var exceedSize: Int64?
            var rejectedForSize = false
            let isMediaReplacement = chatInteraction.presentation.interfaceState.editState?.canEditMedia == true && (files.count == 1 || image != nil)

            
            
            files = files.filter { path -> Bool in
                if let size = fileSize(path.path) {
                    let exceed = fileSizeLimitExceed(context: chatInteraction.interactionContext, fileSize: size)
                    if !exceed { rejectedForSize = true }
                    if exceed {
                        exceedSize = size
                    }
                    return exceed
                }
                return false
            }
            
            let afterSizeCheck = files.count
            
            if afterSizeCheck == 0 && previous != afterSizeCheck {
                if isMediaReplacement {
                }
                showFileLimit(context: chatInteraction.interactionContext, fileSize: exceedSize)
                return false
            }
            if afterSizeCheck < previous {
            }
            if let peer = chatInteraction.presentation.peer, let permissionText = permissionText(from: peer, for: .banSendMedia) {
                if !files.isEmpty || image != nil {
                    if isMediaReplacement {
                    }
                    alert(for: mainWindow, info: permissionText)
                    return false
                }
            }
            
            if files.count == 1, let editState = chatInteraction.presentation.interfaceState.editState, editState.canEditMedia {
                let replacement = chatInteraction.beginMediaReplacement()
                _ = (Sender.generateMedia(for: MediaSenderContainer(path: files[0].path, isFile: false), account: chatInteraction.interactionContext.account, isSecretRelated: chatInteraction.peerId.namespace == Namespaces.Peer.SecretChat) |> deliverOnMainQueue).start(next: { [weak chatInteraction] media, _ in
                    chatInteraction?.applyMediaReplacement(media, request: replacement)
                })
                return false
            } else if let image = image, let editState = chatInteraction.presentation.interfaceState.editState, editState.canEditMedia {
                let replacement = chatInteraction.beginMediaReplacement()
                _ = (putToTemp(image: image, compress: false) |> mapToSignal {Sender.generateMedia(for: MediaSenderContainer(path: regramPastedPhotoPath($0), isFile: false), account: chatInteraction.interactionContext.account, isSecretRelated: chatInteraction.peerId.namespace == Namespaces.Peer.SecretChat) } |> deliverOnMainQueue).start(next: { [weak chatInteraction] media, _ in
                    chatInteraction?.applyMediaReplacement(media, request: replacement)
                })
                return false
            }
            
            if !files.isEmpty {
                chatInteraction.showPreviewSender(files, true, nil)
                return false
            } else if let image = image {
                _ = (putToTemp(image: image, compress: false) |> deliverOnMainQueue).start(next: { [weak chatInteraction] (path) in
                    chatInteraction?.showPreviewSender([URL(fileURLWithPath: regramPastedPhotoPath(path))], true, nil)
                })
                return false
            }
   
        }
        
        
        return true
    }
    
}

