import Cocoa
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import FetchManager

public func regramMessagePhotoInteractiveFetched(context: any AccountContextProtocol, message: Message, image: TelegramMediaImage, userInitiated: Bool, priority: FetchManagerPriority = .userInitiated) -> Signal<Void, NoError> {
    guard let representation = image.representationForDisplayAtSize(.init(width: 1280, height: 1280)) else { return .complete() }
    let reference = AnyMediaReference.message(message: MessageReference(message), media: image)
    return context.fetchManager.interactivelyFetched(category: .image, location: .chat(message.id.peerId), locationKey: .messageId(message.id), mediaReference: reference, resourceReference: reference.resourceReference(representation.resource), ranges: IndexSet(integersIn: 0..<Int(Int32.max)), statsCategory: .image, elevatedPriority: false, userInitiated: userInitiated, priority: priority, storeToDownloadsPeerType: nil)
}
