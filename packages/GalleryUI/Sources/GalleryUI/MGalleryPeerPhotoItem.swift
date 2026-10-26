import Cocoa
import TelegramCore

import Postbox
import SwiftSignalKit
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

public class MGalleryPeerPhotoItem: MGalleryItem {
    public let media:TelegramMediaImage
    private var fullRepresentation: TelegramMediaImageRepresentation? { galleryFullImageRepresentation(media.representations) }
    public override init(_ context: any AccountContextProtocol, _ entry: GalleryEntry, _ pagerSize: NSSize) {
        
        self.media = entry.photo!
        super.init(context, entry, pagerSize)
        
        if let publicPhoto = entry.publicPhoto, let peer = entry.peer as? TelegramUser {
            self.publicPhoto = .init(image: publicPhoto, peer: peer)
        }
    }
    
    public override var sizeValue: NSSize {
        if let largest = fullRepresentation {
            return largest.dimensions.size.fitted(pagerSize)
        }
        return NSZeroSize
    }
    
    public override func smallestValue(for size: NSSize) -> NSSize {
        if let largest = fullRepresentation {
            return largest.dimensions.size.fitted(size)
        }
        return pagerSize
    }
    
    public override var status:Signal<MediaResourceStatus, NoError> {
        if let largestRepresentation = fullRepresentation {
            return context.account.postbox.mediaBox.resourceStatus(largestRepresentation.resource)
        } else {
            return .never()
        }
    }
    
    private var hasRequested: Bool = false

    public override func releaseResources() {
        guard hasRequested else {
            return
        }
        hasRequested = false
        releaseDisplayedImage()
    }

    public override func request(immediately: Bool) {
        super.request(immediately: immediately)
        guard !hasRequested else {
            return
        }
        hasRequested = true
        
        let context = self.context
        let media = self.media
        let entry = self.entry
        
        let sizeValue = size.get() |> distinctUntilChanged
        
        
        let result = combineLatest(sizeValue, rotate.get()) |> mapToSignal { [weak self] size, orientation -> Signal<(NSSize, ImageOrientation?), NoError> in
            guard let `self` = self else {return .complete()}
            var newSize = self.smallestValue(for: size)
            if let orientation = orientation {
                if orientation == .right || orientation == .left {
                    newSize = NSMakeSize(newSize.height, newSize.width)
                }
            }
            return .single((newSize, orientation))
         }
        let representation = fullRepresentation
        let rendered = combineLatest(result, magnify.get() |> distinctUntilChanged, displayScale.get()) |> mapToSignal { value, magnify, scale -> Signal<(NSImage?, ImageOrientation?), NoError> in
            let (originalSize, orientation) = value
            let size = NSMakeSize(ceil(originalSize.width * magnify), ceil(originalSize.height * magnify))
            return chatGalleryPhoto(account: context.account, imageReference: entry.imageReference(media), toRepresentationSize: representation?.dimensions.size ?? size, peer: entry.peer, scale: scale, synchronousLoad: true, fullRepresentation: representation)
                    |> deliverOn(graphicsThreadPool)
                    |> map { transform in
                        let image = transform(TransformImageArguments(corners: ImageCorners(), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets()))
                        if let orientation = orientation {
                            let transformed = image?.createMatchingBackingDataWithImage(orienation: orientation, keepColorSpace: true)
                            if let transformed = transformed {
                                return (NSImage(cgImage: transformed, size: size), orientation)
                            }
                        }
                        if let image = image {
                            return (NSImage(cgImage: image, size: size), orientation)
                        } else {
                            return (nil, nil)
                        }
                }
        }

        if let representation = fullRepresentation  {
            path.set(context.account.postbox.mediaBox.resourceData(representation.resource) |> mapToSignal { (resource) -> Signal<String, NoError> in
                
                if resource.complete {
                    return .single(link(path:resource.path, ext:kMediaImageExt)!)
                }
                return .never()
            })
        } 
        
        self.image.set(rendered |> map { GPreviewValueClass(.image($0.0, $0.1)) } |> deliverOnMainQueue)
        
        
        fetch()
    }
    
    public override func fetch() -> Void {
        let resource = self.entry.peerPhotoResource(representation: fullRepresentation)
        let id = self.entry.peer?.id ?? self.entry.message?.id.peerId
        let userLocation: MediaResourceUserLocation
        if let id = id {
            userLocation = .peer(id)
        } else {
            userLocation = .other
        }
        fetching.set(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: userLocation, userContentType: .image, reference: resource).start())
    }
    
    public override func cancel() -> Void {
        super.cancel()
        if let representation = fullRepresentation  {
            cancelFreeMediaFileInteractiveFetch(context: context, resource: representation.resource)
        }
        fetching.set(nil)
    }

}
