import Cocoa
import CoreText
import ImageIO
import Postbox
import TelegramCore
import TelegramContext
import TelegramTheme
import TelegramUtils
import TGUIKit
import ChatHistoryModel
import ImageCanvasUI
import FilePanels
import AlertsUI
import Localization
import RegramCore
import MessageUtils

private func exportTitle(_ key: String) -> String {
    regramLocalizedString(key, languageCode: appCurrentLanguage.primaryLanguage.languageCode)
}

func regramCanExportMessage(_ message: Message, interaction: ChatInteraction) -> Bool {
    return regramCanSaveMessage(message, accountId: interaction.interactionContext.peerId.toInt64(), cachedData: interaction.presentation.cachedData)
}

func regramMessageView(messageId: MessageId, interaction: ChatInteraction) -> ChatRowView? {
    func find(_ view: NSView) -> ChatRowView? {
        if let row = view as? ChatRowView, let item = row.item as? ChatRowItem,
           item.chatInteraction === interaction, item.entry.messages.contains(where: { $0.id == messageId }) { return row }
        for child in view.subviews {
            if let found = find(child) { return found }
        }
        return nil
    }
    guard Thread.isMainThread, let contentView = interaction.interactionContext.window.contentView else { return nil }
    return find(contentView)
}

func regramLoadedMessages(message: Message, interaction: ChatInteraction) -> [Message] {
    guard let table = regramMessageView(messageId: message.id, interaction: interaction)?.item?.table else { return [] }
    var result: [Message] = []
    var ids = Set<MessageId>()
    table.enumerateItems { item in
        if let item = item as? ChatRowItem, item.chatInteraction === interaction {
            for message in item.entry.messages where ids.insert(message.id).inserted { result.append(message) }
        }
        return true
    }
    return result.sorted { $0.index < $1.index }
}

func regramSelectMessagesFromSender(_ message: Message, interaction: ChatInteraction) -> [MessageId] {
    guard !interaction.disableSelectAbility, !interaction.isLogInteraction, let authorId = message.author?.id else { return [] }
    let threadId = interaction.chatLocation.threadId
    return Array(regramLoadedMessages(message: message, interaction: interaction).reversed().filter {
        $0.author?.id == authorId && $0.id.peerId == interaction.peerId && $0.id.namespace == Namespaces.Message.Cloud
            && (threadId == nil || $0.threadId == threadId) && !$0.media.contains(where: { $0 is TelegramMediaAction })
    }.prefix(100).map(\.id))
}

private func regramExportSnapshot(_ view: NSView) -> CGImage? {
    guard view.bounds.width > 0, view.bounds.height > 0, view.bounds.width * view.bounds.height <= 12_000_000 else { return nil }
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.cgImage
}

private func regramDrawExportText(_ text: String, font: NSFont, color: NSColor, at point: CGPoint, context: CGContext) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
    context.textMatrix = .identity
    context.textPosition = point
    CTLineDraw(line, context)
}

private func regramMessageScreenshot(message: Message, row: ChatRowView) -> CGImage? {
    guard let item = row.item as? ChatRowItem, item.entry.messages.count == 1 else { return nil }
    let bodyViews: [View] = ([row.contentView] + row.captionViews.filter { $0.id == message.stableId }.map(\.view)).filter { $0.bounds.width > 0 && $0.bounds.height > 0 }
    let colors = bodyViews.map(\.backgroundColor)
    for view in bodyViews { view.backgroundColor = .clear }
    defer { for (view, color) in zip(bodyViews, colors) { view.backgroundColor = color } }
    let bodies = bodyViews.compactMap { view -> (CGImage, CGSize)? in
        guard let image = regramExportSnapshot(view) else { return nil }
        return (image, view.bounds.size)
    }
    guard !bodies.isEmpty, bodies.count == bodyViews.count else { return nil }
    let name = (message.author ?? message.peers[message.id.peerId])?.displayTitle ?? exportTitle("messageExport.unknownSender")
    let bodyWidth = max(180, bodies.map { $0.1.width }.max() ?? 180)
    let bodyHeight = bodies.reduce(CGFloat(0)) { $0 + $1.1.height + 4 }
    let size = CGSize(width: 60 + bodyWidth + 12, height: 12 + 26 + bodyHeight + 28)
    let scale = min(2.0, sqrt(12_000_000 / (size.width * size.height)), 16_384 / size.height)
    guard scale > 0, let context = CGContext(data: nil, width: Int(ceil(size.width * scale)), height: Int(ceil(size.height * scale)), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(theme.colors.background.cgColor)
    context.fill(CGRect(origin: .zero, size: size))
    let avatarRect = CGRect(x: 12, y: size.height - 50, width: 38, height: 38)
    context.saveGState()
    context.addEllipse(in: avatarRect)
    context.clip()
    if let avatar = row.photoView.flatMap(regramExportSnapshot) {
        context.draw(avatar, in: avatarRect)
    } else {
        context.setFillColor(theme.colors.grayBackground.cgColor)
        context.fill(avatarRect)
        regramDrawExportText(String(name.prefix(1)), font: .medium(18), color: theme.colors.text, at: CGPoint(x: 23, y: size.height - 38), context: context)
    }
    context.restoreGState()
    let nameLine = CTLineCreateWithAttributedString(NSAttributedString(string: name, attributes: [.font: NSFont.medium(15), .foregroundColor: theme.colors.text]))
    let truncation = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [.font: NSFont.medium(15), .foregroundColor: theme.colors.text]))
    context.textPosition = CGPoint(x: 60, y: size.height - 27)
    CTLineDraw(CTLineCreateTruncatedLine(nameLine, Double(bodyWidth), .end, truncation) ?? nameLine, context)
    var top: CGFloat = 38
    for (image, dimensions) in bodies {
        context.draw(image, in: CGRect(x: 60, y: size.height - top - dimensions.height, width: dimensions.width, height: dimensions.height))
        top += dimensions.height + 4
    }
    regramDrawExportText("Regram", font: .medium(11), color: theme.colors.grayText, at: CGPoint(x: size.width - 55, y: 10), context: context)
    return context.makeImage()
}

private func regramSaveScreenshot(_ image: CGImage, interaction: ChatInteraction) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("regram-message-\(UUID().uuidString).png")
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { try? FileManager.default.removeItem(at: url); return }
    savePanel(file: url.path, ext: "png", for: interaction.interactionContext.window, defaultName: "Regram-Message.png", completion: { _ in try? FileManager.default.removeItem(at: url) })
}

func regramExportMessage(_ message: Message, interaction: ChatInteraction, annotate: Bool) {
    guard let row = regramMessageView(messageId: message.id, interaction: interaction),
          let current = (row.item as? ChatRowItem)?.entry.messages.first(where: { $0.id == message.id }),
          regramCanExportMessage(current, interaction: interaction),
          let image = regramMessageScreenshot(message: current, row: row) else {
        alert(for: interaction.interactionContext.window, info: exportTitle("messageExport.unavailable"))
        return
    }
    if annotate {
        let editor = EditImageCanvasController(image: image, actions: [], context: interaction.interactionContext, updatedImage: { paintings, entities in
            let data = EditedImageData(originalUrl: URL(fileURLWithPath: "/"), paintings: paintings, entities: entities)
            regramSaveScreenshot(data.makeImage(image, interface: false), interaction: interaction)
        }, closeHandler: {}, alone: true)
        showModal(with: editor, for: interaction.interactionContext.window)
    } else {
        regramSaveScreenshot(image, interaction: interaction)
    }
}
