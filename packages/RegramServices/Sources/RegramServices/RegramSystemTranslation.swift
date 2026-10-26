import AppKit
import SwiftUI
import Translation
import SwiftSignalKit

private var regramSystemTranslationViews: [UUID: NSView] = [:]
private var regramSystemTranslationWindowObservers: [UUID: NSObjectProtocol] = [:]

private func regramRemoveSystemTranslation(_ id: UUID) {
    regramSystemTranslationViews.removeValue(forKey: id)?.removeFromSuperview()
    if let observer = regramSystemTranslationWindowObservers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(observer) }
}

@available(macOS 15.0, *)
private struct RegramSystemTranslationTaskView: View {
    let text: String
    let target: String
    let completion: (String?) -> Void

    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .translationTask(source: nil, target: Locale.Language(identifier: target)) { session in
                do {
                    let availability = LanguageAvailability()
                    let status = try await availability.status(for: text, to: Locale.Language(identifier: target))
                    guard status != .unsupported else {
                        await MainActor.run { completion(nil) }
                        return
                    }
                    let response = try await session.translate(text)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { completion(response.targetText) }
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run { completion(nil) }
                }
            }
    }
}

@available(macOS 15.0, *)
private struct RegramSystemTranslationPresentation: View {
    let text: String
    let dismissed: () -> Void
    @State private var presented = false

    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .translationPresentation(isPresented: $presented, text: text)
            .onAppear { presented = true }
            .onChange(of: presented) { value in if !value { dismissed() } }
    }
}

public func regramSystemTranslate(text: String, to: String) -> Signal<String, TranslateFetchError> {
    Signal { subscriber in
        let id = UUID()
        let cancelled = Atomic(value: false)
        DispatchQueue.main.async {
            guard !cancelled.with({ $0 }) else { return }
            guard #available(macOS 15.0, *), let window = NSApp.keyWindow ?? NSApp.mainWindow, let content = window.contentView else { subscriber.putError(.network); return }
            let host = NSHostingView(rootView: RegramSystemTranslationTaskView(text: text, target: to, completion: { result in
                guard !cancelled.with({ $0 }) else { regramRemoveSystemTranslation(id); return }
                if let result { subscriber.putNext(result); subscriber.putCompletion() }
                else { subscriber.putError(.network) }
                regramRemoveSystemTranslation(id)
            }))
            host.frame = NSRect(x: content.bounds.midX, y: content.bounds.midY, width: 1, height: 1)
            regramSystemTranslationViews[id] = host
            regramSystemTranslationWindowObservers[id] = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                if !cancelled.swap(true) { subscriber.putError(.outdated) }
                regramRemoveSystemTranslation(id)
            }
            content.addSubview(host)
        }
        return ActionDisposable {
            _ = cancelled.swap(true)
            DispatchQueue.main.async { regramRemoveSystemTranslation(id) }
        }
    }
}

@discardableResult
public func regramPresentSystemTranslation(text: String, window: NSWindow) -> Bool {
    guard #available(macOS 15.0, *) else { return false }
    DispatchQueue.main.async {
        guard let content = window.contentView else { return }
        let id = UUID()
        let host = NSHostingView(rootView: RegramSystemTranslationPresentation(text: text, dismissed: { regramRemoveSystemTranslation(id) }))
        host.frame = NSRect(x: content.bounds.midX, y: content.bounds.midY, width: 1, height: 1)
        regramSystemTranslationViews[id] = host
        regramSystemTranslationWindowObservers[id] = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in regramRemoveSystemTranslation(id) }
        content.addSubview(host)
    }
    return true
}
