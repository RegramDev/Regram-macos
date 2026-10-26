import Postbox
import TelegramContext
import InputDataUI

public func RegramChatSettingsController(context: any AccountContextProtocol, peerId: PeerId, focusSetting: String? = nil) -> InputDataController {
    RegramChatPreferencesController(context: context, peerId: peerId, focusSetting: focusSetting)
}
