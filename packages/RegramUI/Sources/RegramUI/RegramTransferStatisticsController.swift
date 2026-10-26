import TelegramContext
import InputDataUI

public func RegramTransferStatisticsController(context: any AccountContextProtocol) -> InputDataController {
    RegramDiagnosticsController(context: context, focusSetting: "transfer")
}
