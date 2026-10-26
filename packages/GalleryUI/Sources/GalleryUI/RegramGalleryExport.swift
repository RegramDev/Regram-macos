import Postbox
import TelegramCore
import ChatHistoryModel
import TelegramContext
import SwiftSignalKit
import Cocoa
import TGUIKit
import MessageUtils

extension GalleryEntry {
    func regramCanExport(accountId: Int64, cachedData: CachedPeerData? = nil) -> Bool {
        guard !paidMedia else { return false }
        if let message { return regramCanSaveMessage(message, accountId: accountId, cachedData: cachedData) }
        return !isProtected
    }
}

func regramValidateGalleryExport(context: any AccountContextProtocol, entry: GalleryEntry, permitsProtectedOverride: Bool = true) -> Signal<Bool, NoError> {
    guard let original = entry.message else { return .single(entry.regramCanExport(accountId: context.peerId.toInt64())) }
    return context.account.postbox.transaction { transaction in
        guard let current = transaction.getMessage(original.id), current.stableVersion == original.stableVersion else { return false }
        let cachedData = transaction.getPeerCachedData(peerId: current.id.peerId)
        guard permitsProtectedOverride || !current.isCopyProtected(cachedData: cachedData) else { return false }
        return regramCanSaveMessage(current, accountId: context.peerId.toInt64(), cachedData: cachedData)
    }
}

func regramSaveGalleryFile(path: String, window: Window, isCurrent: @escaping () -> Bool, validate: @escaping () -> Signal<Bool, NoError>) {
    let panel = NSSavePanel()
    let source = URL(fileURLWithPath: path)
    panel.nameFieldStringValue = source.lastPathComponent
    let level = window.level
    window.level = .normal
    panel.begin { response in
        window.level = level
        guard response == .OK, let destination = panel.url, source.standardizedFileURL != destination.standardizedFileURL, isCurrent() else { return }
        _ = (validate() |> deliverOnMainQueue).startStandalone(next: { allowed in
            guard allowed, isCurrent() else { return }
            let temporary = destination.deletingLastPathComponent().appendingPathComponent(".regram-export-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            do {
                try FileManager.default.copyItem(at: source, to: temporary)
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
                } else {
                    try FileManager.default.moveItem(at: temporary, to: destination)
                }
            } catch { NSAlert(error: error).beginSheetModal(for: window) }
        })
    }
}
