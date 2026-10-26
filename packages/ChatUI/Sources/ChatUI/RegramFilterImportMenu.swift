import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext
import ChatHistoryModel
import RegramCore

func regramFilterImportData(for data: ChatMenuItemsData) -> Signal<Data?, NoError> {
    let context = data.chatInteraction.interactionContext
    guard data.file != nil, let resource = data.resourceData, resource.complete,
          resource.size <= Int64(RegramFilterImport.maximumBytes),
          regramCanSaveMessage(data.message, accountId: context.peerId.toInt64(), cachedData: data.cachedData) else { return .single(nil) }
    return Signal { subscriber in
        subscriber.putNext((try? RegramFilterImport.read(from: URL(fileURLWithPath: resource.path)))?.data)
        subscriber.putCompletion()
        return EmptyDisposable
    } |> runOn(Queue.concurrentDefaultQueue())
}
