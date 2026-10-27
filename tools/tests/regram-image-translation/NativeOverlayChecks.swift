func nativeImage() -> CGImage {
    let context = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
    return context.makeImage()!
}
func detection(_ text: String, x: CGFloat = 0.2, y: CGFloat = 0.3) -> TextRecognizing.Result.Detected {
    .init(text: text, language: "en", _topLeft: .init(CGPoint(x: x, y: y + 0.05)), _topRight: .init(CGPoint(x: x + 0.3, y: y + 0.05)), _bottomLeft: .init(CGPoint(x: x, y: y)), _bottomRight: .init(CGPoint(x: x + 0.3, y: y)), _boundingBox: .init(CGRect(x: x, y: y, width: 0.3, height: 0.05)))
}
func layers(_ view: NSView, _ property: String) -> [CALayer] {
    Mirror(reflecting: view).children.first { $0.label == property }!.value as! [CALayer]
}
_ = TestBootstrap.installed
NSApp.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
let nativeView = TextRecognizing.ImageTextSelector.TranslateView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
window.contentView = nativeView
let image = nativeImage()
func result(_ count: Int) -> TextRecognizing.Result { .finish(image: image, text: (0..<count).map { detection("Line \($0)", y: CGFloat($0 + 1) / 20) }, barcodes: []) }
nativeView.set(.progress(result(8)))
precondition(layers(nativeView, "shimmers").count == 8)
nativeView.set(.progress(result(3)))
precondition(layers(nativeView, "shimmers").count == 3)
let values = [TextRecognizing.TranslateResult.Value(text: "Translation", detected: detection("Source", x: 0.2, y: 0.3)), TextRecognizing.TranslateResult.Value(text: "Second", detected: detection("Second source", x: 0.4, y: 0.5))]
nativeView.set(.success(translated: values, original: result(8)))
precondition(layers(nativeView, "shimmers").isEmpty && layers(nativeView, "texts").count == 2)
precondition(abs(layers(nativeView, "texts")[0].frame.minX - 160) < 0.1)
nativeView.set(.success(translated: Array(values.prefix(1)), original: result(8)))
precondition(layers(nativeView, "texts").count == 1)
nativeView.setFrameSize(NSSize(width: 400, height: 300))
nativeView.layout()
precondition(abs(layers(nativeView, "texts")[0].frame.minX - 80) < 0.1)
nativeView.set(.progress(result(0)))
precondition(layers(nativeView, "texts").isEmpty && layers(nativeView, "shimmers").isEmpty)
nativeView.set(.success(translated: values, original: result(0)))
precondition(layers(nativeView, "texts").count == 2)
nativeView.set(.success(translated: [], original: result(8)))
precondition(layers(nativeView, "texts").isEmpty)
nativeView.set(.progress(result(5)))
precondition(layers(nativeView, "shimmers").count == 5)
precondition(!window.isVisible)
window.close()
print("Hidden native overlay checks passed: shrink, retry, mismatched original counts, Value.detected geometry, zero rows and resize; synthetic CGImage only, no visible window.")
