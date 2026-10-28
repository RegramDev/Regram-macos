import AppKit
import ImageIO
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit

@main struct NativeChecks {
    static var failures: [String] = []
    static var checks = 0
    static var observations: [[String: Any]] = []
    static var output: URL!

    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        if !value() { failures.append(label) }
    }

    static func drain() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }

    static func save(_ image: CGImage, _ name: String) {
        let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(name).appendingPathExtension("png") as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        check(CGImageDestinationFinalize(destination), "save \(name)")
    }

    static func pixels(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 512 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 512, height: 512))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 512 * 512 * 4))
    }

    static func contrast(_ image: CGImage, row: Int) -> Double {
        let data = pixels(image)
        var sum = 0.0
        for x in stride(from: 18, to: 490, by: 8) {
            sum += abs(Double(data[(row * 512 + x) * 4]) - Double(data[(row * 512 + x + 4) * 4]))
        }
        return sum / 59
    }

    static func photos() {
        let context = CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 512 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for y in stride(from: 0, to: 512, by: 4) {
            for x in stride(from: 0, to: 512, by: 4) {
                context.setFillColor(CGColor(gray: (x / 4 + y / 4) % 2 == 0 ? 1 : 0, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        let original = context.makeImage()!
        let data = NSBitmapImageRep(cgImage: original).representation(using: .jpeg, properties: [.compressionFactor: 0.8, .progressive: true])!
        let bytes = [UInt8](data)
        let scans = (0 ..< bytes.count - 1).filter { bytes[$0] == 0xff && bytes[$0 + 1] == 0xda }
        check(scans.count >= 4, "fixture contains progressive scans")
        let prefix = Data(data.prefix(scans[2]))
        let tiny = NSBitmapImageRep(cgImage: original).representation(using: .jpeg, properties: [.compressionFactor: 0.1])!
        for scale: CGFloat in [1, 2] {
            let size = NSSize(width: 512, height: 512)
            let arguments = TransformImageArguments(corners: ImageCorners(radius: 12), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets(), resizeMode: .none)
            for (name, value) in [("partial", ImageRenderData(nil, prefix, false)), ("partial-with-thumbnail", ImageRenderData(tiny, prefix, false)), ("complete", ImageRenderData(nil, data, true))] {
                let transform = regressionPhoto(data: value, scale: scale)
                let drawing = transform.execute(arguments, value)!
                let image = drawing.generateImage()!
                let top = contrast(image, row: 62)
                let bottom = contrast(image, row: 450)
                observations.append(["case": name, "scale": scale, "topContrast": top, "bottomContrast": bottom])
                check(image.width == Int(512 * scale) && image.height == Int(512 * scale), "\(name) output dimensions at \(scale)")
                check(drawing.isHighQuality == value.fullSizeComplete, "\(name) quality at \(scale)")
                if value.fullSizeComplete {
                    check(top > 220 && bottom > 220, "complete image is sharp in both halves at \(scale)")
                } else {
                    check(top < 25 && bottom < 25, "partial scan never displays a sharp half at \(scale)")
                }
                check(abs(top - bottom) < 15, "\(name) both halves have consistent detail at \(scale)")
                check(pixels(image)[3] < 20, "\(name) rounded corner alpha at \(scale)")
                save(image, "\(name)-\(Int(scale))x")
            }
        }
    }

    static func inputs() {
        let window = NSWindow(contentRect: NSRect(x: 420, y: 240, width: 640, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(host)
        let input = ChatInputTextView(frame: NSRect(x: 100, y: 40, width: 380, height: 40))
        host.addSubview(input)
        input.updateLayout(size: input.frame.size, textHeight: 40, transition: .immediate)
        let editor = input.inputView
        check(window.makeFirstResponder(editor), "composer accepts focus")
        for prefix in ["", "📌 中文 ", String(repeating: "多行中文 text 📌\n", count: 15)] {
            editor.unmarkText()
            input.attributedText = NSAttributedString(string: prefix, attributes: [.font: NSFont.systemFont(ofSize: 14)])
            editor.setSelectedRange(NSRange(location: prefix.utf16.count, length: 0))
            let height = input.textHeightForWidth(input.frame.width)
            input.updateLayout(size: input.frame.size, textHeight: height, transition: .immediate)
            for count in 1...30 {
                editor.setMarkedText(String(repeating: "s", count: count), selectedRange: NSRange(location: count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                editor.scrollRangeToVisible(editor.selectedRange())
                let selection = editor.selectedRange()
                let marked = editor.markedRange()
                let string = editor.string
                var actual = NSRange(location: NSNotFound, length: 0)
                let caret = editor.firstRect(forCharacterRange: selection, actualRange: nil)
                let unspecified = editor.firstRect(forCharacterRange: NSRange(location: NSNotFound, length: 0), actualRange: &actual)
                check(unspecified.height > 0, "unspecified range has coordinates \(prefix.utf16.count)/\(count)")
                check(unspecified == caret, "unspecified range matches current caret \(prefix.utf16.count)/\(count)")
                check(actual.location != NSNotFound && NSMaxRange(actual) <= string.utf16.count, "valid actual range \(prefix.utf16.count)/\(count)")
                let invalid = editor.firstRect(forCharacterRange: NSRange(location: string.utf16.count + 500, length: Int.max), actualRange: &actual)
                check(invalid == caret, "out of bounds request clamps to caret \(prefix.utf16.count)/\(count)")
                let visible = window.convertToScreen(editor.convert(editor.visibleRect, to: nil))
                check(visible.insetBy(dx: -2, dy: -2).intersects(caret), "caret stays in visible input \(prefix.utf16.count)/\(count)")
                check(editor.string == string && editor.markedRange() == marked && editor.selectedRange() == selection, "coordinate query preserves composition \(prefix.utf16.count)/\(count)")
            }
        }
        editor.unmarkText()
        input.attributedText = NSAttributedString(string: "中文 📌 ", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.setMarkedText("ceshi", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        input.updateLayout(size: input.frame.size, textHeight: input.textHeightForWidth(input.frame.width), transition: .immediate)
        editor.scrollRangeToVisible(editor.selectedRange())
        let range = NSRange(location: NSNotFound, length: 0)
        var before = editor.firstRect(forCharacterRange: range, actualRange: nil)
        host.frame.origin.x += 31
        host.frame.origin.y += 19
        var after = editor.firstRect(forCharacterRange: range, actualRange: nil)
        check(abs(after.minX - before.minX - 31) < 0.5 && abs(after.minY - before.minY - 19) < 0.5, "candidate follows ancestor movement")
        for origin in [NSPoint(x: -750, y: 180), NSPoint(x: 1800, y: 380)] {
            before = editor.firstRect(forCharacterRange: range, actualRange: nil)
            let oldOrigin = window.frame.origin
            window.setFrameOrigin(origin)
            after = editor.firstRect(forCharacterRange: range, actualRange: nil)
            check(abs(after.minX - before.minX - window.frame.minX + oldOrigin.x) < 0.5 && abs(after.minY - before.minY - window.frame.minY + oldOrigin.y) < 0.5, "candidate follows window including negative screen coordinates")
        }
        drain()
        check(window.firstResponder === editor && editor.hasMarkedText(), "geometry refresh preserves focus and composition")
        let other = NSTextView(frame: NSRect(x: 0, y: 200, width: 100, height: 40))
        host.addSubview(other)
        check(window.makeFirstResponder(other), "focus can transfer to another editor")
        for index in 0..<10 { host.frame.origin.x = CGFloat(index) }
        drain()
        check(window.firstResponder === other, "late geometry refresh never steals focus")
        check(!window.isVisible && !window.isKeyWindow && !window.isMainWindow, "test window stays invisible and inactive")
    }

    static func photoData() {
        for (knownSize, sizes) in [(true, [100, 200, 400, 600, 1600]), (false, [100, 200, 400, 600, 1600]), (true, [100, 200, 400, 600, 800, 1600]), (false, [100, 200, 400, 600, 800, 1600])] {
            let directory = output.appendingPathComponent("media-\(knownSize)-\(UUID().uuidString)")
            let mediaBox = MediaBox(basePath: directory.path, isMainProcess: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let data = Data((0..<1600).map { UInt8($0 % 251) })
            let resource = CloudPhotoSizeMediaResource(datacenterId: 1, photoId: 10, accessHash: 0, sizeSpec: "x", size: knownSize ? Int64(data.count) : nil, fileReference: nil)
            let representation = TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: 1280, height: 1280), resource: resource, progressiveSizes: sizes.map(Int32.init), immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
            let image = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 10), representations: [representation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
            let reference = ImageMediaReference.standalone(media: image)
            var values: [ImageRenderData] = []
            var completed = false
            let requestedRanges = Atomic<[Range<Int64>]>(value: [])
            mediaBox.fetchResource = { _, ranges, _ in
                return Signal { subscriber in
                    ranges.start(next: { ranges in
                        _ = requestedRanges.modify { $0 + ranges.map { $0.0 } }
                        guard let range = ranges.first?.0 else { return }
                        let upperBound = min(data.count, Int(clamping: range.upperBound))
                        let part = Data(data.prefix(upperBound))
                        subscriber.putNext(.dataPart(resourceOffset: 0, data: part, range: 0 ..< Int64(upperBound), complete: upperBound == data.count))
                        subscriber.putCompletion()
                    })
                }
            }
            mediaBox.storeResourceData(resource.id, range: 0..<200, data: Data(data.prefix(200)))
            let disposable = (regressionPhotoDatas(postbox: FixturePostbox(mediaBox: mediaBox), imageReference: reference, fullRepresentationSize: NSSize(width: 350, height: 350), synchronousLoad: true) |> deliverOnMainQueue).start(next: { values.append($0) }, completed: { completed = true })
            defer { disposable.dispose() }
            let partialDeadline = Date(timeIntervalSinceNow: 2)
            while values.last?.fullSizeData == nil && Date() < partialDeadline { drain() }
            check(values.contains(where: { $0.fullSizeData?.count == 200 && !$0.fullSizeComplete }), "partial data stays incomplete, known size \(knownSize)")
            check(!completed, "partial data leaves subscription live, known size \(knownSize)")
            check(requestedRanges.with { $0.isEmpty }, "passive preview does not start download, known size \(knownSize)")
            let fetch = regressionPhotoDatas(postbox: FixturePostbox(mediaBox: mediaBox), imageReference: reference, fullRepresentationSize: NSSize(width: 350, height: 350), autoFetchFullSize: true).start()
            defer { fetch.dispose() }
            let fullDeadline = Date(timeIntervalSinceNow: 3)
            while !completed && Date() < fullDeadline { drain() }
            check(requestedRanges.with { $0.contains(where: { $0.upperBound >= data.count }) }, "automatic fetch requests complete image, known size \(knownSize)")
            check(completed, "full file completes subscription, known size \(knownSize)")
            check(values.last?.fullSizeData == data && values.last?.fullSizeComplete == true, "full file replaces partial preview, known size \(knownSize)")
            let count = values.count
            drain()
            check(values.count == count, "no events after completed photo, known size \(knownSize)")
            var cached: [ImageRenderData] = []
            var cachedComplete = false
            let cachedDisposable = (regressionPhotoDatas(postbox: FixturePostbox(mediaBox: mediaBox), imageReference: reference, fullRepresentationSize: NSSize(width: 1280, height: 1280), synchronousLoad: true) |> deliverOnMainQueue).start(next: { cached.append($0) }, completed: { cachedComplete = true })
            defer { cachedDisposable.dispose() }
            let cachedDeadline = Date(timeIntervalSinceNow: 2)
            while !cachedComplete && Date() < cachedDeadline { drain() }
            check(cachedComplete && cached.last?.fullSizeData == data && cached.last?.fullSizeComplete == true, "complete cached progressive image stays sharp, known size \(knownSize)")
        }
    }

    static func inputMethods() {
        let profiles: [(name: String, prefix: String, preedits: [String], committed: String)] = [
            ("simplified-pinyin", "简体中文 📌 ", ["c", "ce", "ce shi", "测试"], "测试"),
            ("traditional-zhuyin", "繁體中文臺灣 📌 ", ["ㄘ", "ㄘㄜˋ", "ㄘㄜˋㄕˋ", "測試"], "測試"),
            ("traditional-cangjie", "繁體中文香港 📌 ", ["a", "ab", "日月", "明"], "明"),
            ("traditional-pinyin", "繁體拼音 📌 ", ["c", "ce", "ce shi", "測試"], "測試"),
            ("japanese-kana", "日本語 𠮷 👩🏽‍💻 ", ["k", "ka", "かな", "漢字かな交じり文"], "漢字かな交じり文"),
            ("korean-hangul", "한국어 📌 ", ["ㅎ", "하", "한", "한ㄱ", "한국어", "한"], "한국어"),
            ("latin-dead-keys", "Français Deutsch 📌 ", ["e", "e\u{301}", "é", "o\u{308}", "ö", "a\u{302}\u{301}"], "éöấ"),
            ("vietnamese", "Tiếng Việt 📌 ", ["a", "a\u{302}", "a\u{302}\u{301}", "ấ"], "Tiếng Việt"),
            ("right-to-left", "العربية עברית 📌 ", ["ع", "عربي", "עברית", "العربية עברית"], "العربية עברית")
        ]
        for width: CGFloat in [140, 380] {
            let window = NSWindow(contentRect: NSRect(x: 420, y: 240, width: 640, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let input = ChatInputTextView(frame: NSRect(x: 100, y: 40, width: width, height: 70))
            window.contentView!.addSubview(input)
            let editor = input.inputView
            let suffix = " 後續文字"
            check(window.makeFirstResponder(editor), "multilingual composer accepts focus at \(width)")
            for profile in profiles {
                let startChecks = checks
                let startFailures = failures.count
                editor.unmarkText()
                input.attributedText = NSAttributedString(string: profile.prefix + suffix, attributes: [.font: NSFont.systemFont(ofSize: 14)])
                editor.setSelectedRange(NSRange(location: profile.prefix.utf16.count, length: 0))
                for text in profile.preedits {
                    let nsText = text as NSString
                    var clusters: [NSRange] = []
                    nsText.enumerateSubstrings(in: NSRange(location: 0, length: nsText.length), options: .byComposedCharacterSequences) { _, range, _, _ in clusters.append(range) }
                    let selections = [NSRange(location: 0, length: 0), clusters[0], NSRange(location: clusters[clusters.count / 2].location, length: 0), NSRange(location: nsText.length, length: 0)]
                    for selection in selections {
                        let label = "\(profile.name)/\(width)/\(text)/\(selection)"
                        let markedText = NSAttributedString(string: text, attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue, .markedClauseSegment: 0])
                        editor.setMarkedText(markedText, selectedRange: selection, replacementRange: NSRange(location: NSNotFound, length: 0))
                        input.updateLayout(size: input.frame.size, textHeight: input.textHeightForWidth(width), transition: .immediate)
                        editor.scrollRangeToVisible(editor.selectedRange())
                        let string = editor.string
                        let marked = editor.markedRange()
                        let selected = editor.selectedRange()
                        check(string == profile.prefix + text + suffix, "preedit only replaces marked text \(label)")
                        check(marked == NSRange(location: profile.prefix.utf16.count, length: nsText.length), "preedit uses UTF16 ranges \(label)")
                        check(selected == NSRange(location: profile.prefix.utf16.count + selection.location, length: selection.length), "preedit preserves selected candidate clause \(label)")
                        let caret = editor.firstRect(forCharacterRange: NSRange(location: selected.location, length: 0), actualRange: nil)
                        var actual = NSRange(location: NSNotFound, length: 0)
                        let unknown = editor.firstRect(forCharacterRange: NSRange(location: NSNotFound, length: 0), actualRange: &actual)
                        check(unknown.height > 0 && unknown == caret, "unknown range anchors current caret \(label)")
                        check(actual.location != NSNotFound && NSMaxRange(actual) <= string.utf16.count, "unknown actual range remains valid \(label)")
                        let visible = window.convertToScreen(editor.convert(editor.visibleRect, to: nil))
                        check(visible.insetBy(dx: -2, dy: -2).contains(unknown.origin), "candidate anchor stays visible \(label)")
                        for cluster in clusters {
                            let requested = NSRange(location: profile.prefix.utf16.count + cluster.location, length: cluster.length)
                            let rect = editor.firstRect(forCharacterRange: requested, actualRange: &actual)
                            check(rect.height > 0 && rect.origin.x.isFinite && rect.origin.y.isFinite, "explicit cluster has screen coordinates \(label)/\(cluster)")
                            check(actual.location != NSNotFound && NSMaxRange(actual) <= string.utf16.count, "cluster actual range remains valid \(label)/\(cluster)")
                        }
                        check(editor.hasMarkedText() && editor.string == string && editor.markedRange() == marked && editor.selectedRange() == selected, "coordinate queries preserve composition and candidate selection \(label)")
                        check(window.firstResponder === editor, "coordinate queries preserve focus \(label)")
                    }
                }
                let marked = editor.markedRange()
                let replacement = "修訂 👩🏽‍💻"
                editor.setMarkedText(replacement, selectedRange: NSRange(location: replacement.utf16.count, length: 0), replacementRange: marked)
                check(editor.string == profile.prefix + replacement + suffix, "explicit preedit replacement \(profile.name)/\(width)")
                editor.insertText(profile.committed, replacementRange: NSRange(location: NSNotFound, length: 0))
                check(editor.string == profile.prefix + profile.committed + suffix && !editor.hasMarkedText(), "committing candidate preserves surrounding text \(profile.name)/\(width)")
                let end = NSRange(location: editor.string.utf16.count, length: 0)
                editor.setSelectedRange(end)
                editor.setMarkedText("cancel", selectedRange: NSRange(location: 6, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                editor.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                check(editor.string == profile.prefix + profile.committed + suffix && !editor.hasMarkedText(), "cancelling preedit removes only pending text \(profile.name)/\(width)")
                observations.append(["case": profile.name, "width": width, "checks": checks - startChecks, "failures": failures.count - startFailures, "validationLevel": "NSTextInputClient marked-text contract", "realInputMethodEngineExercised": false])
            }
            drain()
            check(!window.isVisible && !window.isKeyWindow && !window.isMainWindow, "multilingual test window stays inactive at \(width)")
        }
    }

    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        if CommandLine.arguments.contains("--input-methods-only") {
            inputMethods()
        } else {
            photos()
            inputs()
            photoData()
            inputMethods()
        }
        let report: [String: Any] = ["checks": checks, "failures": failures, "observations": observations, "macOS": ProcessInfo.processInfo.operatingSystemVersionString]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("report.json"))
        print("native checks=\(checks), failures=\(failures.count)")
        for failure in failures.prefix(15) { print(failure) }
        exit(failures.isEmpty ? 0 : 1)
    }
}
