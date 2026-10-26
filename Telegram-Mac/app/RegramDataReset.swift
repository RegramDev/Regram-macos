import Cocoa
import Security
import ApiCredentials
import RegramCore

func restartRegramApplication() {
    guard Bundle.main.bundleIdentifier == RegramDataResetScope.bundleIdentifier else { return }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open -n \"$2\"", "regram-restart", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
    do { try task.run(); NSApplication.shared.terminate(nil) }
    catch { NSAlert(error: error).runModal() }
}

func requestRegramFullWipe(language: String) {
    UserDefaults.standard.set(true, forKey: "rg_full_wipe")
    UserDefaults.standard.set(language, forKey: "Regram.Reset.Language")
    UserDefaults.standard.synchronize()
    exit(0)
}

func runRegramFullWipeIfRequested() {
    guard Bundle.main.bundleIdentifier == RegramDataResetScope.bundleIdentifier,
          UserDefaults.standard.bool(forKey: "rg_full_wipe") else { return }
    let language = UserDefaults.standard.string(forKey: "Regram.Reset.Language") ?? Locale.preferredLanguages.first ?? "en"
    func text(_ key: String) -> String { regramLocalizedString(key, languageCode: language) }
    _ = NSApplication.shared
    let confirmation = NSAlert()
    confirmation.alertStyle = .critical
    confirmation.messageText = text("EraseData.Title")
    confirmation.informativeText = text("EraseData.Confirm")
    confirmation.addButton(withTitle: text("Common.Cancel"))
    confirmation.addButton(withTitle: text("EraseData.Action"))
    guard confirmation.runModal() == .alertSecondButtonReturn else {
        UserDefaults.standard.removeObject(forKey: "rg_full_wipe")
        UserDefaults.standard.synchronize()
        exit(0)
    }
    let manager = FileManager.default
    var targets: [URL] = []
    var failures: [String] = []
    for location in [FileManager.SearchPathDirectory.applicationSupportDirectory, .cachesDirectory] {
        if let root = manager.urls(for: location, in: .userDomainMask).first,
           let directory = RegramDataResetScope.applicationDirectory(root: root) { targets.append(directory) }
        else { failures.append(location == .applicationSupportDirectory ? "Application Support" : "Caches") }
    }
    if !ApiEnvironment.teamId.isEmpty {
        if let directory = manager.containerURL(forSecurityApplicationGroupIdentifier: ApiEnvironment.group),
           let validated = RegramDataResetScope.groupDirectory(directory, identifier: ApiEnvironment.group) { targets.append(validated) }
        else { failures.append("App Group") }
    }
    let progress = NSAlert()
    progress.messageText = text("EraseData.Progress")
    let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 240, height: 18))
    spinner.isIndeterminate = true
    spinner.startAnimation(nil)
    progress.accessoryView = spinner
    progress.window.makeKeyAndOrderFront(nil)
    for target in Set(targets) where manager.fileExists(atPath: target.path) {
        do { try manager.removeItem(at: target) }
        catch { failures.append(target.lastPathComponent) }
    }
    var previousInteraction = DarwinBoolean(true)
    let interactionStatus = SecKeychainGetUserInteractionAllowed(&previousInteraction)
    let disableStatus = interactionStatus == errSecSuccess ? SecKeychainSetUserInteractionAllowed(false) : interactionStatus
    var attributes: CFTypeRef?
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecReturnAttributes as String: true,
                                kSecMatchLimit as String: kSecMatchLimitAll,
                                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
    let status = disableStatus == errSecSuccess ? SecItemCopyMatching(query as CFDictionary, &attributes) : disableStatus
    if status == errSecSuccess {
        let items = (attributes as? [[String: Any]]) ?? (attributes as? [String: Any]).map { [$0] }
        if items == nil { failures.append("Keychain") }
        let services = Set((items ?? []).compactMap { $0[kSecAttrService as String] as? String }.filter(RegramDataResetScope.ownsKeychainService))
        for service in services {
            let deletion: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                           kSecAttrService as String: service,
                                           kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
            let result = SecItemDelete(deletion as CFDictionary)
            if result != errSecSuccess && result != errSecItemNotFound { failures.append("Keychain") }
        }
    } else if status != errSecItemNotFound || disableStatus != errSecSuccess { failures.append("Keychain") }
    if interactionStatus == errSecSuccess && disableStatus == errSecSuccess {
        if SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) != errSecSuccess { failures.append("Keychain") }
    }
    UserDefaults.standard.removePersistentDomain(forName: RegramDataResetScope.bundleIdentifier)
    UserDefaults.standard.removePersistentDomain(forName: RegramDataResetScope.bundleIdentifier + ".share")
    if RegramDataResetScope.ownsAppGroupIdentifier(ApiEnvironment.group) {
        UserDefaults(suiteName: ApiEnvironment.group)?.removePersistentDomain(forName: ApiEnvironment.group)
    }
    if !failures.isEmpty {
        UserDefaults.standard.set(true, forKey: "rg_full_wipe")
        UserDefaults.standard.set(language, forKey: "Regram.Reset.Language")
    }
    UserDefaults.standard.synchronize()
    progress.window.orderOut(nil)
    let result = NSAlert()
    result.messageText = text(failures.isEmpty ? "EraseData.Done" : "EraseData.Errors")
    result.informativeText = failures.isEmpty ? text("EraseData.DoneNotice") : String(format: text("EraseData.ErrorsNotice"), Array(Set(failures)).sorted().joined(separator: ", "))
    result.addButton(withTitle: text("EraseData.Close"))
    result.runModal()
    exit(0)
}
