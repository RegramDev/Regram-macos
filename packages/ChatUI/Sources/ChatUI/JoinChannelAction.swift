import Cocoa
import TelegramCore
import Localization
import Postbox
import SwiftSignalKit
import TGUIKit
import InAppSettings
import ColorPalette
import ThemeSettings
import TelegramTheme
import TelegramContext
import AlertsUI
import InputDataUI


public func joinChannel(context: any AccountContextProtocol, peerId: PeerId) {
    let signal = context.engine.peers.joinChannel(peerId: peerId, hash: nil) |> take(1) |> deliverOnMainQueue
    _ = (showModalProgress(signal: signal, for: context.window)).start(next: { outcome in
        switch outcome {
        case .joined:
            _ = (showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 1.5)).start()
            FeatureNavigationHooks.shared.presentRegramFolderAfterJoining?(context, peerId)
        case let .webView(webView):
            ChatNavigationHooks.shared.openJoinChatBotWebViewObserved(context, webView.botPeer.id, webView.url, webView.queryId, peerId)
        }
    }, error: { error in
        let text: String
        switch error {
        case .generic:
            text = strings().unknownError
        case .tooMuchJoined:
            ChatNavigationHooks.shared.showInactiveChannelsOnJoinObserved(context)
            return
        case .tooMuchUsers:
            text = strings().groupUsersTooMuchError
        case .inviteRequestSent:
            showModalText(for: context.window, text: strings().chatSendJoinRequestInfo, title: strings().chatSendJoinRequestTitle)
            return
        }
        alert(for: context.window, info: text)
    })
}
