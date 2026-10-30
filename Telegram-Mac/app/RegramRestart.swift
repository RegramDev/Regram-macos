import Cocoa
import RegramCore

func restartRegramApplication() {
    guard Bundle.main.bundleIdentifier == RegramDataResetScope.bundleIdentifier else { return }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open -n \"$2\"", "regram-restart", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
    do { try task.run(); NSApplication.shared.terminate(nil) }
    catch { NSAlert(error: error).runModal() }
}

