import Cocoa
import AVFoundation
import TGUIKit
import GeneralRows
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import Localization
import InputDataUI
import RegramServices

private final class RegramCapturePreviewItem: GeneralRowItem {
    let session: AVCaptureSession
    let active: Bool
    init(_ size: NSSize, stableId: AnyHashable, session: AVCaptureSession, active: Bool) {
        self.session = session
        self.active = active
        super.init(size, height: 320, stableId: stableId, viewType: .singleItem)
    }
    override func viewClass() -> AnyClass { RegramCapturePreviewView.self }
}

private final class RegramCapturePreviewView: GeneralContainableRowView {
    private let preview = AVCaptureVideoPreviewLayer()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        preview.videoGravity = .resizeAspectFill
        containerView.layer?.addSublayer(preview)
    }
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? RegramCapturePreviewItem else { return }
        preview.session = item.active ? item.session : nil
        needsLayout = true
    }
    override func layout() { super.layout(); preview.frame = containerView.bounds }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

public func RegramMediaCaptureController(context: any AccountContextProtocol, previewEnabled: Bool = true, completion: @escaping (URL) -> Void) -> InputDataModalController {
    var close: () -> Void = {}
    let session = RegramMediaCaptureSession(maximumVideoDuration: context.isPremium ? 180 : 60) { result in
        if case let .success(url) = result { close(); completion(url) }
    }
    let signal = combineLatest(session.state |> deliverOnMainQueue, appearanceSignal) |> map { state, _ -> InputDataSignalValue in
        var page = RegramPageBuilder(page: "capture")
        page.section()
        page.custom("preview", equatable: InputDataEquatable(state.phase)) { size, id in RegramCapturePreviewItem(size, stableId: id, session: session.captureSession, active: state.phase != .idle && state.phase != .failed) }
        if state.phase == .idle || state.phase == .failed {
            page.row("start", title: strings().callCamera, action: session.start)
        } else if state.phase == .ready {
            page.row("photo", title: regramString("Camera.PhotoMode"), action: session.takePhoto)
            page.row("video", title: regramString("Camera.VideoMode"), action: session.startRecording)
        } else if state.phase == .recording {
            page.row("stop", title: regramString("VoiceOver.Recording.StopAndPreview") + String(format: "  %d:%02d", state.seconds / 60, state.seconds % 60), action: session.stopRecording)
        } else { page.row("working", title: strings().callCamera, type: .loading, enabled: false) }
        if let error = state.error {
            page.text(error == .cameraDenied || error == .microphoneDenied ? regramString(error == .cameraDenied ? "AccessDenied.Camera" : "AccessDenied.VideoMicrophone") : strings().callCameraError)
            if error == .cameraDenied || error == .microphoneDenied {
                page.row("settings", title: regramString("AccessDenied.Settings"), action: {
                    let path = error == .cameraDenied ? "Privacy_Camera" : "Privacy_Microphone"
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + path) { NSWorkspace.shared.open(url) }
                })
            }
        }
        page.row("cancel", title: strings().modalCancel, action: { session.cancel(); close() })
        return InputDataSignalValue(entries: page.entries)
    }
    let controller = RegramFormController(dataSignal: signal, title: strings().callCamera, didLoad: { _, _ in if previewEnabled { session.start() } }, hasDone: false)
    controller.onDeinit = { session.cancel() }
    let modal = InputDataModalController(controller, closeHandler: { done in session.cancel(); done() }, size: NSMakeSize(380, 490))
    close = { [weak modal] in modal?.close() }
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { session.cancel(); close() })
    return modal
}
