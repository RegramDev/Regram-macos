import Foundation
import Cocoa
import TGUIKit
import AppKit



@available(macOS 10.15, *)
public extension TextRecognizing {
    
    final class ImageTextSelector : View {
        
        class TranslateView : View {
            
            
            private class DrawingTextLayer: SimpleLayer {
                let textView = TextView()
                override init() {
                    super.init()
                    textView.lockDrawingLayer = true
                    self.addSublayer(textView.drawingLayer)
                    
                    textView.drawingLayer.transform = CATransform3DMakeRotation(.pi, 1, 0, 0)
                }
                
                required init?(coder: NSCoder) {
                    fatalError("init(coder:) has not been implemented")
                }
                func set(translated: TextRecognizing.TranslateResult.Value, rect: NSRect, maxWidth: CGFloat) -> NSRect {
                    
                    let font = fontSizeThatFits(text: translated.text, in: rect, initialFont: .medium(30), minFontSize: 10)
                    
                    let textLayout = TextViewLayout(.initialize(string: translated.text, color: NSColor.black, font: font), maximumNumberOfLines: 1)
                    
                    textLayout.measure(width: maxWidth - rect.minX)
                    textView.update(textLayout)
                    
                    textView.drawingLayer.frame = textLayout.layoutSize.bounds //rect.focusY(textLayout.layoutSize, x: 0)
                    
                    return NSMakeRect(rect.minX, rect.minY, max(textView.frame.width, rect.width), max(textView.frame.height, rect.height))
                }
            }
            
            private var shimmers: [ShimmerLayer] = []
            private var texts: [DrawingTextLayer] = []
            
            private var backgroundImage: SimpleLayer?
            private var currentTranslation: TranslateResult?
            private var renderedSize = NSSize.zero

            required init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                isEventLess = true
            }
            
            override var isFlipped: Bool {
                return false
            }
            
            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
            
            func set(_ translate: TranslateResult) {
                currentTranslation = translate
                renderedSize = bounds.size
                guard bounds.width > 0, bounds.height > 0 else {
                    shimmers.forEach { $0.removeFromSuperlayer() }
                    texts.forEach { $0.removeFromSuperlayer() }
                    shimmers.removeAll()
                    texts.removeAll()
                    backgroundImage?.removeFromSuperlayer()
                    backgroundImage = nil
                    return
                }
                func validRect(_ rect: CGRect) -> Bool {
                    rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
                }
                switch translate {
                case let .progress(result):
                    
                    if let backgroundImage {
                        performSublayerRemoval(backgroundImage, animated: true)
                    }
                    backgroundImage = nil
                    
                    for text in texts {
                        performSublayerRemoval(text, animated: true)
                    }
                    texts.removeAll()
                    
                    let regions = zip(result.selectableRects(viewSize: bounds.size), result.rotations()).filter { validRect($0.0) && $0.1.isFinite }
                    
                    while shimmers.count > regions.count {
                        shimmers.removeLast().removeFromSuperlayer()
                    }
                    while shimmers.count < regions.count {
                        let current = ShimmerLayer()
                        shimmers.append(current)
                        self.layer?.addSublayer(current)
                        current.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                    
                    for (i, shimmerView) in shimmers.enumerated() {
                        let value = regions[i].0
                        let rotation = regions[i].1
                        shimmerView.cornerRadius = 4
                        shimmerView.masksToBounds = true
                        shimmerView.update(backgroundColor: .blackTransparent, data: nil, size: value.size, imageSize: value.size)
                        shimmerView.updateAbsoluteRect(value.size.bounds, within: value.size)
                        shimmerView.frame = value
                        shimmerView.transform = CATransform3DMakeRotation(rotation, 0, 0, 1)
                    }
                    
                case let .success(translated, _):
                    for shimmer in shimmers {
                        performSublayerRemoval(shimmer, animated: true)
                    }
                    shimmers.removeAll()
                    let regions = translated.compactMap { value -> (TranslateResult.Value, CGRect, CGFloat)? in
                        let rect = value.detected.frameRect
                        let frame = NSMakeRect(rect.minX * bounds.width, rect.minY * bounds.height, rect.width * bounds.width, rect.height * bounds.height)
                        let rotation = value.detected.rotationAngle
                        guard validRect(frame), rotation.isFinite else { return nil }
                        return (value, frame, rotation)
                    }
                    var rects = regions.map { $0.1 }
                    let rotations = regions.map { $0.2 }

                    while texts.count > regions.count { texts.removeLast().removeFromSuperlayer() }
                    while texts.count < rects.count {
                        let current = DrawingTextLayer()
                        texts.append(current)
                        self.layer?.addSublayer(current)
                        current.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                    for (i, text) in texts.enumerated() {
                        let rotation = rotations[i]
                        
                        rects[i] = text.set(translated: regions[i].0, rect: rects[i], maxWidth: frame.width)
                        text.frame = rects[i]
                        text.transform = CATransform3DMakeRotation(rotation, 0, 0, 1)
                    }
                    
                    do {
                        let current: SimpleLayer
                        if let layer = self.backgroundImage {
                            current = layer
                        } else {
                            current = SimpleLayer()
                            self.backgroundImage = current
                            self.layer?.insertSublayer(current, at: 0)
                            current.animateAlpha(from: 0, to: 1, duration: 0.2)
                        }
                        current.frame = self.bounds
                        
                        current.contents = generateImage(self.bounds.size, contextGenerator: { size, ctx in
                            ctx.clear(size.bounds)
                            ctx.setFillColor(.white)
                            for (index, rect) in rects.enumerated() {
                                let rect = rect.insetBy(dx: -4, dy: -4)
                                let rotationAngle = rotations[index]

                                ctx.saveGState()

                                let centerX = rect.midX
                                let centerY = rect.midY
                                ctx.translateBy(x: centerX, y: centerY)
                                ctx.rotate(by: rotationAngle)
                                ctx.translateBy(x: -centerX, y: -centerY)
                                ctx.fill(rect)
                                ctx.setFillColor(NSColor.grayForeground.withAlphaComponent(0.5).cgColor)
                                ctx.fill(rect)
                                ctx.restoreGState()
                            }
                        })
                    }

                }
            }
            
            override func layout() {
                super.layout()
                if renderedSize != bounds.size, let currentTranslation { set(currentTranslation) }
            }
        }
        
        
        private var trackingArea:NSTrackingArea?

        
        public private(set) var result: Result?
        private var showRects: Bool = false
        private var translate: TranslateResult? = nil
        private var startPoint: NSPoint? = nil
        private var currentPoint: NSPoint? = nil
        private var finished: Bool = false
        private let linearProgress = LinearProgressControl(progressHeight: 2)
        
        private var translateView: TranslateView?
        
        private(set) var barcodeOverlays: [BarcodeOverlay] = []
        private var subjectOverlay: SimpleLayer?
        
        public var openBarcode: ((Result.Barcode) -> Void)?
        public var barcodeMenu: ((Result.Barcode) -> ContextMenu?)?
        
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(linearProgress)
            linearProgress.style = .init(foregroundColor: NSColor.systemBlue.withAlphaComponent(0.6))
        }
        
        public override func updateTrackingAreas() {
            super.updateTrackingAreas();
            
            if let trackingArea = trackingArea {
                self.removeTrackingArea(trackingArea)
            }
            
            trackingArea = nil
            
            if let _ = window {
                let options:NSTrackingArea.Options = [NSTrackingArea.Options.cursorUpdate, NSTrackingArea.Options.mouseEnteredAndExited, NSTrackingArea.Options.mouseMoved, NSTrackingArea.Options.activeInKeyWindow, NSTrackingArea.Options.inVisibleRect]
                self.trackingArea = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
                
                self.addTrackingArea(self.trackingArea!)
            }
            
        }
        
        public override func mouseUp(with event: NSEvent) {
            //super.mouseUp(with: event)
            self.finishSelect(event)
        }
        public override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            self.startSelect(event)
        }
        public override func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)
            self.processSelect(event)
        }

        public override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            self.cursorUpdate(with: event)
        }
        
        public override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            self.cursorUpdate(with: event)
            self.updateBarcodeProximity(nil)
        }
        
        public override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            self.cursorUpdate(with: event)
            self.updateBarcodeProximity(self.convert(event.locationInWindow, from: nil))
        }
        
        func updateBarcodeProximity(_ point: NSPoint?, animated: Bool = true) {
            for overlay in barcodeOverlays {
                overlay.reveal(point.map { overlay.isNear($0) } ?? false, animated: animated)
            }
        }
        
        public override func cursorUpdate(with event: NSEvent) {
            super.cursorUpdate(with: event)
            
            guard let result = result else {
                return
            }
            
            var cursor: NSCursor = NSCursor.arrow
            
            let point = self.convert(event.locationInWindow, from: nil)
            
            if barcodeOverlays.contains(where: { $0.contains(point) }) {
                NSCursor.pointingHand.set()
                return
            }
            let paths = result.selectablePaths(viewSize: self.frame.size)
            
            for path in paths {
                if path.contains(point) {
                    cursor = NSCursor.iBeam
                    break
                }
            }
            cursor.set()
        }
        
        private var realStartPoint: NSPoint?
        private func startSelect(_ event: NSEvent) {
            self.realStartPoint = self.convert(event.locationInWindow, from: nil)
        }
        private func processSelect(_ event: NSEvent) {
            let current = self.convert(event.locationInWindow, from: nil)
            if let from = self.realStartPoint {
                let w = max(current.x, from.x) - min(current.x, from.x)
                let h = max(current.y, from.y) - min(current.y, from.y)
                if w < 1 && h < 1 {
                    return
                }
            }
            
            if self.finished || self.startPoint == nil {
                self.startPoint = self.convert(event.locationInWindow, from: nil)
            }
            self.currentPoint = current
            self.finished = false
            self.needsDisplay = true
        }
        private func finishSelect(_ event: NSEvent) {
            if self.finished || (result == nil || result!.inProgress) {
                cancelSelection()
            } else {
                self.finished = true
                self.realStartPoint = nil
                self.needsDisplay = true
            }
           
        }
        
        public override func layout() {
            super.layout()
            linearProgress.frame = NSMakeRect(0, 0, frame.width, linearProgress.frame.height)
            translateView?.frame = bounds
            for overlay in barcodeOverlays {
                overlay.layout(in: frame.size)
            }
            subjectOverlay?.frame = bounds
        }
        
        public override var isFlipped: Bool {
            return false
        }
                
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public override func draw(_ layer: CALayer, in ctx: CGContext) {
            super.draw(layer, in: ctx)
            guard let result = result else {
                return
            }
            
            
            if self.showRects {
                let paths = result.selectablePaths(viewSize: self.frame.size)
                for path in paths {
                    ctx.setFillColor(NSColor.white.withAlphaComponent(0.2).cgColor)
                    ctx.addPath(path)
                    ctx.fillPath()
                }
            }
            
            if let updated = self.selectedResult {
                
                if !self.finished {
                    if let from = self.startPoint, let to = self.currentPoint {
                        let selected = NSMakeRect(min(from.x, to.x), min(from.y, to.y), max(from.x, to.x) - min(from.x, to.x), max(from.y, to.y) - min(from.y, to.y))
                        ctx.setFillColor(NSColor.lightGray.withAlphaComponent(0.6).cgColor)
                        ctx.fill(selected)
                    }
                }
                
                let paths = updated.selectablePaths(viewSize: self.frame.size)
                for path in paths {
                    ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.4).cgColor)
                    ctx.addPath(path)
                    ctx.fillPath()
                }
            }
        }
        
        var selectedResult: Result? {
            if let from = self.startPoint, let to = self.currentPoint, let result = self.result {
                return result.select(from: from, to: to, viewSize: self.frame.size)
            }
            return nil
        }
        
        public func set(_ result: Result?, translate: TranslateResult? = nil, showRects: Bool = false) {
            self.result = result
            self.showRects = showRects
            self.translate = translate
            self.userInteractionEnabled = result != nil && translate == nil
            self.isEventLess = result == nil
            
            if let result = result {
                switch result {
                case let .progress(progress):
                    self.linearProgress.set(progress: CGFloat(progress), animated: true)
                    self.linearProgress.change(opacity: 1)
                default:
                    self.linearProgress.change(opacity: 0)
                }
            }
            
            if let translate {
                let current: TranslateView
                if let view = self.translateView {
                    current = view
                } else {
                    current = TranslateView(frame: bounds)
                    self.translateView = current
                    addSubview(current)
                }
                current.set(translate)
            } else if let view = self.translateView {
                performSubviewRemoval(view, animated: false)
                self.translateView = nil
            }
            
            updateBarcodes(result?.barcodes ?? [])
            
            needsDisplay = true
        }
        
        private func updateBarcodes(_ barcodes: [Result.Barcode]) {
            guard barcodeOverlays.map({ $0.barcode }) != barcodes else {
                return
            }
            for overlay in barcodeOverlays {
                overlay.remove(animated: true)
            }
            barcodeOverlays = barcodes.map { barcode in
                return BarcodeOverlay(barcode: barcode, superview: self, action: { [weak self] barcode in
                    self?.openBarcode?(barcode)
                }, menu: { [weak self] barcode in
                    return self?.barcodeMenu?(barcode)
                })
            }
            for overlay in barcodeOverlays {
                overlay.layout(in: frame.size)
            }
            if let window = window, !barcodeOverlays.isEmpty {
                let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                updateBarcodeProximity(NSPointInRect(point, bounds) ? point : nil)
            }
        }
        
        public func normalizedPoint(fromWindow point: NSPoint) -> CGPoint? {
            let point = self.convert(point, from: nil)
            guard frame.width > 0, frame.height > 0, NSPointInRect(point, bounds) else {
                return nil
            }
            return CGPoint(x: point.x / frame.width, y: point.y / frame.height)
        }
        
        public func showLiftedSubject(_ image: CGImage, rect: CGRect, completion: @escaping () -> Void) {
            subjectOverlay?.removeFromSuperlayer()
            
            let container = SimpleLayer()
            container.frame = bounds
            
            let dim = SimpleLayer()
            dim.frame = bounds
            dim.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
            container.addSublayer(dim)
            
            let subjectFrame = NSMakeRect(rect.minX * frame.width, rect.minY * frame.height, rect.width * frame.width, rect.height * frame.height)
            let subject = SimpleLayer()
            subject.frame = subjectFrame
            subject.contents = image
            subject.contentsGravity = .resize
            subject.shadowColor = NSColor.white.cgColor
            subject.shadowRadius = 10
            subject.shadowOffset = .zero
            subject.shadowOpacity = 0.9
            container.addSublayer(subject)
            
            self.layer?.addSublayer(container)
            self.subjectOverlay = container
            
            dim.animateAlpha(from: 0, to: 1, duration: 0.25)
            subject.animateScaleSpring(from: 1, to: 1.04, duration: 0.4, removeOnCompletion: false, bounce: true, center: false)
            
            let glow = CAKeyframeAnimation(keyPath: "shadowOpacity")
            glow.values = [0, 0.95, 0.6]
            glow.keyTimes = [0, 0.35, 1]
            glow.duration = 0.7
            subject.add(glow, forKey: "glow")
            subject.shadowOpacity = 0.6
            
            delay(0.85, closure: { [weak self, weak container] in
                guard let container else {
                    return
                }
                container.animateAlpha(from: 1, to: 0, duration: 0.25, removeOnCompletion: false, completion: { [weak self, weak container] _ in
                    container?.removeFromSuperlayer()
                    if self?.subjectOverlay === container {
                        self?.subjectOverlay = nil
                    }
                })
                completion()
            })
        }
        
        public var hasSelectedText: Bool {
            if let selectedResult = selectedResult {
                return !selectedResult.selectablePaths(viewSize: self.frame.size).isEmpty
            }
            return false
        }
        public func cancelSelection() {
            self.startPoint = nil
            self.currentPoint = nil
            self.realStartPoint = nil
            self.finished = false
            self.needsDisplay = true
        }
        public func copySelectedText() -> Bool {
            if let selectedText = self.selectedText {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(selectedText, forType: .string)
                return true
            }
            return false
        }
        
        public var selectedText: String? {
            if let selectedResult = self.selectedResult {
                switch selectedResult {
                case let .finish(_, texts, _):
                    if !texts.isEmpty {
                        var string: String = ""
                        for value in texts {
                            string += value.text
                            if value != texts.last {
                                string += "\n"
                            }
                        }
                        return string
                    }
                default:
                    break
                }
            }
            return nil
        }
    }
    
}
