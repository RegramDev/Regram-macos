import AppKit
import QuartzCore
import RegramCore

public final class RegramSeasonalEffectView: NSView {
    private let accountId: Int64
    private var observers: [NSObjectProtocol] = []
    private var emitter: CAEmitterLayer?
    private var style: String?
    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { false }

    public init(accountId: Int64, frame: NSRect) {
        self.accountId = accountId
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        autoresizingMask = [.width, .height]
        observers.append(NotificationCenter.default.addObserver(forName: RegramPreferences.didChange, object: nil, queue: .main) { [weak self] notification in
            guard let self, notification.object as? Int64 == self.accountId else { return }
            self.refresh()
        })
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.updateActivity() })
        }
        refresh()
    }

    public static func attach(to view: NSView, accountId: Int64) {
        guard !view.subviews.contains(where: { $0 is RegramSeasonalEffectView }) else { return }
        view.addSubview(RegramSeasonalEffectView(accountId: accountId, frame: view.bounds))
    }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func refresh() {
        let selected = RegramPreferences.shared.settings(accountId: accountId).seasonalEffect
        guard selected != style else { updateActivity(); return }
        style = selected
        emitter?.removeFromSuperlayer()
        emitter = nil
        guard let selected, let image = RegramBranding.effectImage(lightning: selected == "lightning") else { isHidden = true; return }
        isHidden = false
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            if let context = NSGraphicsContext.current?.cgContext { context.setBlendMode(.sourceIn); context.setFillColor(NSColor.white.cgColor); context.fill(rect) }
            return true
        }
        var imageRect = NSRect(origin: .zero, size: image.size)
        let cell = CAEmitterCell()
        cell.contents = tinted.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
        cell.name = selected
        cell.scale = selected == "lightning" ? 0.15 : 0.04
        cell.scaleRange = selected == "lightning" ? 0.25 : 0.15
        var rate: Float = 10
        var lowPower = false
        if #available(macOS 12.0, *) { lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        if lowPower || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { rate /= 3 }
        cell.birthRate = rate
        cell.lifetime = 55
        cell.velocity = 1
        cell.velocityRange = -1.5
        cell.xAcceleration = 0.33
        cell.yAcceleration = 1
        cell.emissionRange = .pi
        cell.spin = -28.6 * (.pi / 180)
        cell.spinRange = 57.2 * (.pi / 180)
        cell.color = NSColor.white.withAlphaComponent(0.58).cgColor
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .circle
        emitter.emitterMode = .surface
        emitter.renderMode = .oldestLast
        emitter.emitterCells = [cell]
        self.emitter = emitter
        layer?.addSublayer(emitter)
        needsLayout = true
        updateActivity()
    }

    private func updateActivity() { emitter?.birthRate = window != nil && NSApplication.shared.isActive ? 1 : 0 }
    public override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateActivity() }
    public override func layout() {
        super.layout()
        emitter?.frame = bounds
        emitter?.emitterPosition = CGPoint(x: 0, y: -bounds.height / 8)
        emitter?.emitterSize = CGSize(width: bounds.width * 1.5, height: bounds.height)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) }; emitter?.removeFromSuperlayer() }
}
