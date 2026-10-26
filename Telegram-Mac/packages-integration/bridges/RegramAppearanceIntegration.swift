import Cocoa
import TelegramTheme
import SwiftSignalKit
import TGUIKit
import RegramCore
import RegramServices

private final class RegramFontAppearanceBinding {
    private static let lock = NSLock()
    private static var active: UUID?
    private let token = UUID()
    private let accountId: Int64
    private var observers: [NSObjectProtocol] = []
    private var configuration: [String: RegramValue] = [:]

    init(accountId: Int64, window: Window?) {
        self.accountId = accountId
        if let window {
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in self?.activate() })
        }
        activate()
        observers.append(NotificationCenter.default.addObserver(forName: RegramPreferences.didChange, object: nil, queue: .main) { [weak self] notification in
            guard let self, notification.object as? Int64 == self.accountId else { return }
            self.refresh()
        })
        observers.append(NotificationCenter.default.addObserver(forName: RegramFontStore.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isActive else { return }
            InterfaceFontProvider.invalidate()
        })
    }

    private var isActive: Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return Self.active == token
    }

    private func activate() {
        Self.lock.lock()
        Self.active = token
        Self.lock.unlock()
        let accountId = accountId
        InterfaceFontProvider.install { size, weight, italic in
            RegramFonts.interfaceFont(size: size, weight: weight, italic: italic, accountId: accountId)
        }
        refresh(force: true)
    }

    private func refresh(force: Bool = false) {
        let settings = RegramPreferences.shared.settings(accountId: accountId)
        let keys = ["fontFamily", "fontChineseFamily", "fontImportedLatin", "fontImportedChinese", "fontApplyToMessages", "fontApplyToInterface"]
        let current = Dictionary(uniqueKeysWithValues: keys.map { ($0, settings[$0]) })
        guard force || current != configuration else { return }
        configuration = current
        RegramFontStore.shared.retainSelections(settings: settings, accountId: accountId)
        if isActive {
            InterfaceFontProvider.invalidate()
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        Self.lock.lock()
        let wasActive = Self.active == token
        if wasActive { Self.active = nil }
        Self.lock.unlock()
        if wasActive { InterfaceFontProvider.install(nil) }
    }
}

func bindRegramFonts(accountId: Int64, window: Window? = nil) -> Disposable {
    let binding = RegramFontAppearanceBinding(accountId: accountId, window: window)
    return ActionDisposable { _ = binding }
}
