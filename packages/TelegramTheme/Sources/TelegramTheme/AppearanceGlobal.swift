import Cocoa
import TelegramCore
import Localization
import Postbox
import SwiftSignalKit
import TGUIKit

public final class Appearance : Equatable {
    public let language: TelegramLocalization
    public var presentation: TelegramPresentationTheme
    public init(language: TelegramLocalization, presentation: TelegramPresentationTheme) {
        self.language = language
        self.presentation = presentation
    }
    
    public var languageCode: String {
        return language.baseLanguageCode.replacingOccurrences(of: "-raw", with: "")
    }
    
    public var locale: Locale {
        return Locale(identifier: appAppearance.language.languageCode)
    }
    
    public var newAllocation: Appearance {
        return Appearance(language: language, presentation: presentation)
    }
}

public func ==(lhs:Appearance, rhs:Appearance) -> Bool {
    return lhs.language === rhs.language && lhs.presentation === rhs.presentation
}

public var theme: TelegramPresentationTheme {
    if let presentation = presentation as? TelegramPresentationTheme {
        return presentation
    }
    TelegramThemeHooks.shared.setDefaultTheme(nil)
    return presentation as! TelegramPresentationTheme
}

public var redActionButton: ControlStyle {
    return ControlStyle(font: NSFont.normal(.title), foregroundColor: theme.colors.redUI)
}

public func generateSettingsIcon(_ icon: CGImage) -> CGImage {
    return generateImage(NSMakeSize(24, 24), contextGenerator: { size, ctx in
        ctx.clear(CGRect(origin: CGPoint(), size: size))
        ctx.setFillColor(.white)
        ctx.fill(size.bounds.insetBy(dx: 3, dy: 3))
        ctx.draw(icon, in: CGRect(origin: CGPoint(), size: size))
    }, scale: System.backingScale)!
}

public var blueActionButton: ControlStyle {
    return ControlStyle(font: NSFont.normal(.title), foregroundColor: theme.colors.accent)
}

public var appAppearance:Appearance {
    return Appearance(language: appCurrentLanguage, presentation: theme)
}

private final class AppearanceDayContext {
    static let shared = AppearanceDayContext()
    
    let day: ValuePromise<Int32>
    private var observers: [NSObjectProtocol] = []
    private var timer: SwiftSignalKit.Timer?
    
    private init() {
        self.day = ValuePromise(AppearanceDayContext.currentDay(), ignoreRepeated: true)
        let day = self.day
        let update: () -> Void = {
            day.set(AppearanceDayContext.currentDay())
        }
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            self.observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil, using: { _ in
                update()
            }))
        }
        let timer = SwiftSignalKit.Timer(timeout: 60.0, repeat: true, completion: update, queue: resourcesQueue)
        self.timer = timer
        timer.start()
    }
    
    private static func currentDay() -> Int32 {
        var now: time_t = time_t(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        var timeinfo: tm = tm()
        localtime_r(&now, &timeinfo)
        return timeinfo.tm_year * 1000 + timeinfo.tm_yday
    }
}

public var appearanceSignal:Signal<Appearance, NoError> {
    
    let updateSignal = AppearanceDayContext.shared.day.get() |> map { _ in true }
    
    return combineLatest(languageSignal, themeSignal, updateSignal |> deliverOnMainQueue, InterfaceFontProvider.changes |> deliverOnMainQueue) |> map {
        return Appearance(language: $0.0, presentation: $0.3 == 0 ? $0.1 : $0.1.new())
    }
}

public final class AppearanceWrapperEntry<E>: Comparable, Identifiable where E: Comparable, E:Identifiable {
    public let entry: E
    public let appearance: Appearance
    public init(entry: E, appearance: Appearance) {
        self.entry = entry
        self.appearance = appearance
    }
    public var stableId: E.T {
        return entry.stableId
    }
}

public func == <E>(lhs:AppearanceWrapperEntry<E>, rhs: AppearanceWrapperEntry<E>) -> Bool {
    return lhs.entry == rhs.entry && lhs.appearance == rhs.appearance
}
public func < <E>(lhs:AppearanceWrapperEntry<E>, rhs: AppearanceWrapperEntry<E>) -> Bool {
    return lhs.entry < rhs.entry
}

