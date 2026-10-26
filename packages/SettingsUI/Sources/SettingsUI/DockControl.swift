import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramTheme
import ColorPalette
import RegramServices

public final class DockControl {
    private let disposable = MetaDisposable()

    public init(_ engine: TelegramEngine, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        disposable.set((combineLatest(RegramBranding.selection, appearanceSignal |> map { $0.presentation.colors.isDark } |> distinctUntilChanged) |> deliverOnMainQueue).start(next: { _, dark in
            RegramBranding.applyCurrentIcon(dark: dark)
        }))
    }

    public func clear() { disposable.dispose() }
    deinit { clear() }
}
