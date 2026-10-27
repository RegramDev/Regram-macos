import Cocoa
import SwiftSignalKit

typealias Window = NSWindow

enum RegramValue: Equatable { case string(String), bool(Bool) }
struct RegramAccountSettings {
    var values: [String: RegramValue]
    subscript(_ key: String) -> RegramValue { values[key] ?? .string("") }
}
final class RegramPreferences {
    static let shared = RegramPreferences()
    static let didChange = Notification.Name("Fixture.RegramPreferencesDidChange")
    var accounts: [Int64: RegramAccountSettings] = [:]
    func settings(accountId: Int64) -> RegramAccountSettings { accounts[accountId] ?? RegramAccountSettings(values: [:]) }
    func set(_ key: String, _ value: RegramValue, accountId: Int64) {
        var settings = self.settings(accountId: accountId)
        settings.values[key] = value
        accounts[accountId] = settings
        NotificationCenter.default.post(name: Self.didChange, object: accountId)
    }
}
final class RegramFontStore {
    static let shared = RegramFontStore()
    static let didChange = Notification.Name("Fixture.RegramFontStoreDidChange")
    var retained: [Int64] = []
    func retainSelections(settings: RegramAccountSettings, accountId: Int64) { retained.append(accountId) }
}
enum RegramFonts {
    static var requests: [(Int64, CGFloat, NSFont.Weight, Bool)] = []
    static func interfaceFont(size: CGFloat, weight: NSFont.Weight, italic: Bool, accountId: Int64) -> NSFont? {
        requests.append((accountId, size, weight, italic))
        let settings = RegramPreferences.shared.settings(accountId: accountId)
        guard settings["fontApplyToInterface"] != .bool(false) else { return nil }
        let offset: CGFloat
        if case let .string(value) = settings["fontFamily"] { offset = CGFloat(Double(value) ?? 0) } else { offset = 0 }
        return .systemFont(ofSize: size + offset, weight: weight)
    }
}
PRODUCTION_FONT_PROVIDER
PRODUCTION_BINDING
PRODUCTION_BIND_FUNCTION

final class FixtureTheme: Equatable {
    static var copies = 0
    let palette: Int
    init(_ palette: Int = 1) { self.palette = palette }
    func new() -> FixtureTheme { Self.copies += 1; return FixtureTheme(palette) }
    static func == (lhs: FixtureTheme, rhs: FixtureTheme) -> Bool { lhs === rhs }
}
struct Appearance { let language: String; let presentation: FixtureTheme }
final class AppearanceDayContext { static let shared = AppearanceDayContext(); let day = ValuePromise<Int32>(1) }
let languageValue = ValuePromise("zh-hans", ignoreRepeated: true)
let themeValue = ValuePromise(FixtureTheme(), ignoreRepeated: true)
var languageSignal: Signal<String, NoError> { languageValue.get() }
var themeSignal: Signal<FixtureTheme, NoError> { themeValue.get() }
PRODUCTION_APPEARANCE_SIGNAL

@main
struct FocusAppearanceChecks {
    static var count = 0
    static var failures: [String] = []
    static var observations: [[String: Any]] = []
    static var appearanceEvents = 0
    static var fontEvents = 0
    static var lastPalette = 0
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        count += 1
        if !condition() { failures.append(label); print("FAIL \(label)") }
    }
    static func key(_ window: NSWindow, times: Int = 1) {
        for _ in 0..<times { NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window) }
    }
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let aWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: .borderless, backing: .buffered, defer: false)
        let bWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: .borderless, backing: .buffered, defer: false)
        aWindow.isReleasedWhenClosed = false; bWindow.isReleasedWhenClosed = false
        defer { aWindow.close(); bWindow.close() }
        RegramPreferences.shared.accounts = [1: .init(values: ["fontFamily": .string("2"), "fontApplyToInterface": .bool(true)]), 2: .init(values: ["fontFamily": .string("20"), "fontApplyToInterface": .bool(true)])]
        let fonts = InterfaceFontProvider.changes.start(next: { _ in fontEvents += 1 })
        let appearances = appearanceSignal.start(next: { appearance in
            appearanceEvents += 1
            lastPalette = appearance.presentation.palette
        })
        var a: Disposable? = bindRegramFonts(accountId: 1, window: aWindow)
        check(InterfaceFontProvider.font(size: 14, weight: .regular)?.pointSize == 16, "first binding installs current account font")
        let firstFontEvents = fontEvents, firstAppearanceEvents = appearanceEvents, firstCopies = FixtureTheme.copies
        let firstRetains = RegramFontStore.shared.retained.count
        key(aWindow, times: 20)
        check(fontEvents == firstFontEvents, "20 same-window key notifications do not invalidate fonts")
        check(appearanceEvents == firstAppearanceEvents && FixtureTheme.copies == firstCopies, "20 same-window key notifications do not rebuild global theme")
        check(RegramFontStore.shared.retained.count == firstRetains, "same binding does not redo retained font selections")
        observations.append(["stage": "20 same-binding focus notifications", "fontInvalidations": fontEvents - firstFontEvents, "appearanceEmissions": appearanceEvents - firstAppearanceEvents, "themeCopies": FixtureTheme.copies - firstCopies, "selectionRetains": RegramFontStore.shared.retained.count - firstRetains])
        let beforeTheme = appearanceEvents
        themeValue.set(FixtureTheme(2))
        check(appearanceEvents == beforeTheme + 1 && lastPalette == 2, "genuine palette change remains live independently of font focus guard")
        let unrelated = fontEvents
        RegramPreferences.shared.set("unrelated", .bool(true), accountId: 1)
        check(fontEvents == unrelated, "unrelated preference does not invalidate appearance")
        let beforeFontChange = fontEvents
        RegramPreferences.shared.set("fontFamily", .string("5"), accountId: 1)
        check(fontEvents == beforeFontChange + 1, "active real font configuration changes invalidate once")
        observations.append(["stage": "active font preference changed", "fontInvalidations": fontEvents - beforeFontChange])
        check(InterfaceFontProvider.font(size: 14, weight: .regular)?.pointSize == 19, "font changes are applied without requiring another focus event")
        let beforeNoopFocus = fontEvents
        key(aWindow)
        check(fontEvents == beforeNoopFocus, "focus after settings refresh does not invalidate twice")
        let beforeMissedChange = fontEvents
        var missedSettings = RegramPreferences.shared.settings(accountId: 1)
        missedSettings.values["fontChineseFamily"] = .string("changed without notification")
        RegramPreferences.shared.accounts[1] = missedSettings
        key(aWindow)
        check(fontEvents == beforeMissedChange + 1, "same-binding focus refreshes genuine configuration change missed by notifications")
        observations.append(["stage": "same binding with missed real configuration change", "fontInvalidations": fontEvents - beforeMissedChange])
        check(InterfaceFontProvider.font(size: 22, weight: .bold, italic: true)?.pointSize == 27, "dynamic requested size remains live through installed provider")
        check(RegramFonts.requests.last?.1 == 22 && RegramFonts.requests.last?.2 == .bold && RegramFonts.requests.last?.3 == true, "dynamic font weight and italic are forwarded")
        RegramPreferences.shared.set("fontApplyToInterface", .bool(false), accountId: 1)
        check(InterfaceFontProvider.font(size: 14, weight: .regular) == nil, "disabling interface fonts restores native fallback")
        RegramPreferences.shared.set("fontApplyToInterface", .bool(true), accountId: 1)
        check(InterfaceFontProvider.font(size: 14, weight: .regular)?.pointSize == 19, "reenabling interface fonts takes effect")
        var b: Disposable? = bindRegramFonts(accountId: 2, window: bWindow)
        check(InterfaceFontProvider.font(size: 14, weight: .regular)?.pointSize == 34, "second account installs its own provider")
        let beforeInactiveChange = fontEvents
        RegramPreferences.shared.set("fontFamily", .string("8"), accountId: 1)
        check(fontEvents == beforeInactiveChange && InterfaceFontProvider.font(size: 14, weight: .regular)?.pointSize == 34, "inactive account preference cannot replace active window font")
        let beforeReturn = fontEvents
        key(aWindow)
        check(fontEvents > beforeReturn && InterfaceFontProvider.font(size: 14, weight: .regular)?.pointSize == 22, "returning to another account window reinstalls latest account font")
        observations.append(["stage": "switch B window to A window", "fontInvalidations": fontEvents - beforeReturn, "activeAccount": RegramFonts.requests.last?.0 ?? -1])
        let beforeStoreChange = fontEvents
        NotificationCenter.default.post(name: RegramFontStore.didChange, object: nil)
        check(fontEvents == beforeStoreChange + 1, "font-store change invalidates only the active binding")
        observations.append(["stage": "font store changed with two bindings", "fontInvalidations": fontEvents - beforeStoreChange])
        key(bWindow)
        check(InterfaceFontProvider.font(size: 14, weight: .regular)?.pointSize == 34, "switching back uses B token rather than stale A configuration")
        let beforeBFocus = fontEvents
        key(bWindow, times: 10)
        check(fontEvents == beforeBFocus, "repeated B-window activation is also idempotent")
        let beforeInactiveDispose = fontEvents
        a?.dispose(); a = nil
        check(fontEvents == beforeInactiveDispose && InterfaceFontProvider.font(size: 14, weight: .regular)?.pointSize == 34, "disposing inactive binding does not clear active provider")
        key(aWindow)
        check(fontEvents == beforeInactiveDispose && InterfaceFontProvider.font(size: 14, weight: .regular)?.pointSize == 34, "disposed old-window notification cannot reinstall stale token")
        b?.dispose(); b = nil
        check(InterfaceFontProvider.font(size: 14, weight: .regular) == nil, "disposing active binding restores native provider")
        let afterDispose = fontEvents
        key(aWindow); key(bWindow)
        NotificationCenter.default.post(name: RegramFontStore.didChange, object: nil)
        check(fontEvents == afterDispose, "disposed bindings release key and font-store observers")
        let sameAccountA = bindRegramFonts(accountId: 1, window: aWindow)
        let sameAccountB = bindRegramFonts(accountId: 1, window: bWindow)
        let beforeSameAccountWindow = fontEvents
        key(aWindow)
        check(fontEvents > beforeSameAccountWindow, "different window binding with same account still takes provider ownership")
        sameAccountA.dispose()
        let afterOldWindowDispose = fontEvents
        key(aWindow)
        check(fontEvents == afterOldWindowDispose, "disposed same-account window cannot reactivate its old token")
        key(bWindow)
        check(InterfaceFontProvider.font(size: 14, weight: .regular)?.pointSize == 22, "remaining same-account window restores its current provider")
        sameAccountB.dispose()
        let finalBinding = bindRegramFonts(accountId: 1)
        check(InterfaceFontProvider.font(size: 14, weight: .regular)?.pointSize == 22, "binding without a window still initializes provider")
        finalBinding.dispose()
        check(!aWindow.isVisible && !bWindow.isVisible && !NSApp.windows.contains { $0.isVisible }, "fixture never presents or activates a window")
        fonts.dispose(); appearances.dispose()
        let report: [String: Any] = ["checks": count, "failures": failures, "observations": observations, "visibleWindows": NSApp.windows.filter { $0.isVisible }.count, "nativeInactiveMaterialChanged": false, "liveApplicationSwitchMeasured": false]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("report.json"))
        print("focus appearance checks=\(count), failures=\(failures.count)")
        if !failures.isEmpty { exit(1) }
    }
}
