import Postbox
import TelegramCore
import RegramSignals
import SwiftSignalKit

public func regramMessageFilterChanges(accountId: Int64) -> Signal<Void, NoError> {
    regramPreferenceChanges(accountId: accountId) |> map { _ in () }
}

public func regramVisibleMessages(_ messages: [Message], accountId: Int64) -> [Message] {
    messages.filter { !regramShouldHideMessage($0, accountId: accountId) }
}

public func regramFilteredSearchResult(_ result: SearchMessagesResult, accountId: Int64) -> SearchMessagesResult {
    SearchMessagesResult(messages: regramVisibleMessages(result.messages, accountId: accountId), readStates: result.readStates, threadInfo: result.threadInfo, totalCount: result.totalCount, completed: result.completed)
}
