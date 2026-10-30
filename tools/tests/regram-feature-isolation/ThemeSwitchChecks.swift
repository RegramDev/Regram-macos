import Foundation
import SwiftSignalKit

func verify(_ condition: @autoclosure () -> Bool, _ message: String = "Fixture assertion failed", line: UInt = #line) {
    guard condition() else {
        FileHandle.standardError.write(Data((message + " at line " + String(line) + "\n").utf8))
        exit(1)
    }
}

struct FixturePalette: Equatable { var id: Int }
struct FixtureWallpaper: Equatable { var wallpaper = 0 }
struct FixtureCloud: Equatable { var id: Int }
struct ThemePaletteSettings: Equatable {
    var palette = FixturePalette(id: 0)
    var bubbled = false
    var wallpaper = FixtureWallpaper()
    var fontSize: CGFloat = 13
    var cloudTheme: FixtureCloud?
    var legacyMenu = false
}
struct TelegramPresentationTheme { let settings: ThemePaletteSettings }
enum System { static var backingScale: CGFloat = 2; static var legacyMenu = false }
let resourcesQueue = Queue(name: "fixture.resources")
let prepared = Atomic(value: [Int]())
let prepareHook = Atomic<((ThemePaletteSettings) -> Void)?>(value: nil)
var applicationEvents: [(Int, Int, Bool)] = []
func telegramUpdateTheme(_ theme: TelegramPresentationTheme, window: Int, animated: Bool) {
    verify(Thread.isMainThread)
    verify(!animated, "Application appearance switches must not capture and cover the window with an obsolete theme")
    applicationEvents.append((theme.settings.palette.id, window, animated))
}
final class FixtureWindowContext {
    let window: Int
    init(_ window: Int) { self.window = window }
}
final class FixtureApplicationContext {
    let context: FixtureWindowContext
    var refreshes = 0
    init(_ window: Int) { context = FixtureWindowContext(window) }
    func applyNewTheme() { refreshes += 1 }
}
final class FixtureThemeApplication {
    var contextValue: Int?
    let window = 1
    var contexts: [FixtureApplicationContext] = []
    func enumerateApplicationContexts(_ body: (FixtureApplicationContext) -> Void) { contexts.forEach(body) }
    func apply(_ updatedTheme: TelegramPresentationTheme?) {
        __APPLY_THEME__
    }
}
func updateTheme(with settings: ThemePaletteSettings) -> TelegramPresentationTheme {
    verify(!Thread.isMainThread)
    _ = prepared.modify { $0 + [settings.palette.id] }
    prepareHook.with { $0 }?(settings)
    return TelegramPresentationTheme(settings: settings)
}
func waitUntil(_ label: String, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(3)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    verify(condition(), label)
}

@main
struct ThemeSwitchChecks {
    static func main() {
        let themeSettings = ThemePaletteSettings()
        let updates = ValuePromise(themeSettings)
        let backingProperties = ValuePromise<CGFloat>(System.backingScale, ignoreRepeated: true)
        let basicTheme = Atomic<ThemePaletteSettings?>(value: themeSettings)
        __THEME_PIPELINE__
        var delivered: [ThemePaletteSettings] = []
        let subscription = signal.start(next: { theme in
            verify(Thread.isMainThread)
            if let theme { delivered.append(theme.settings) }
        })
        defer { subscription.dispose() }
        let resourceBlocked = DispatchSemaphore(value: 0)
        let releaseResource = DispatchSemaphore(value: 0)
        resourcesQueue.async { resourceBlocked.signal(); _ = releaseResource.wait(timeout: .now() + 5) }
        verify(resourceBlocked.wait(timeout: .now() + 2) == .success)
        var settings = themeSettings
        settings.palette.id = 1
        updates.set(settings)
        waitUntil("Theme preparation was blocked by the resource queue") { delivered.last?.palette.id == 1 }
        releaseResource.signal()

        let entered = Atomic(value: false)
        let releasePreparation = DispatchSemaphore(value: 0)
        _ = prepareHook.swap { value in
            if value.palette.id == 2 { _ = entered.swap(true); verify(releasePreparation.wait(timeout: .now() + 4) == .success) }
        }
        settings.palette.id = 2
        updates.set(settings)
        waitUntil("Slow theme did not start") { entered.with { $0 } }
        let count = prepared.with { $0.count }
        for id in 3...102 { settings.palette.id = id; updates.set(settings) }
        updates.set(settings)
        releasePreparation.signal()
        waitUntil("Latest theme did not appear") { delivered.last?.palette.id == 102 }
        verify(delivered.map { $0.palette.id } == [1, 102])
        verify(prepared.with { $0.count } == count + 1)

        settings.palette.id = 103
        updates.set(settings)
        let queued = DispatchSemaphore(value: 0)
        themePreparationQueue.async { queued.signal() }
        verify(queued.wait(timeout: .now() + 2) == .success)
        settings.palette.id = 104
        updates.set(settings)
        waitUntil("New theme did not replace queued old delivery") { delivered.last?.palette.id == 104 }
        verify(!delivered.contains { $0.palette.id == 103 })
        let beforeCloud = delivered.count
        settings.cloudTheme = FixtureCloud(id: 1)
        updates.set(settings)
        waitUntil("Cloud theme identity was ignored") { delivered.count == beforeCloud + 1 }
        let beforeScale = delivered.count
        backingProperties.set(1)
        waitUntil("Backing scale change was ignored") { delivered.count == beforeScale + 1 }
        let beforeDuplicate = prepared.with { $0.count }
        updates.set(settings)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        verify(prepared.with { $0.count } == beforeDuplicate)
        subscription.dispose()
        settings.palette.id = 105
        updates.set(settings)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        verify(delivered.last?.palette.id == 104)
        let application = FixtureThemeApplication()
        let theme = TelegramPresentationTheme(settings: settings)
        application.apply(theme)
        verify(applicationEvents.count == 1 && applicationEvents.last?.1 == 1)
        application.contextValue = 1
        application.contexts = [FixtureApplicationContext(2), FixtureApplicationContext(3)]
        application.apply(theme)
        verify(applicationEvents.map { $0.1 } == [1, 2, 3])
        verify(applicationEvents.allSatisfy { $0.0 == 105 && !$0.2 })
        verify(application.contexts.allSatisfy { $0.refreshes == 1 })
        application.apply(nil)
        verify(applicationEvents.count == 3)
        print("Application theme production pipeline passed: independent resource queue, 100 obsolete requests skipped, in-flight and queued-main cancellation, cloud identity, scale changes, duplicate suppression, disposal and snapshot-free application to each window; synthetic settings/renderer, real SwiftSignalKit")
    }
}
