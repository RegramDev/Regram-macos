from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
PRODUCTS = Path.home() / "Library/Caches/RegramReleaseDerivedData-arm64/Build/Products/Release"


def declaration(source, marker):
    if source.count(marker) != 1:
        raise RuntimeError("Review the changed production boundary: " + marker)
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    index = opening + 1
    while depth:
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
        index += 1
    return source[start:index]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--products", type=Path, default=PRODUCTS)
    args = parser.parse_args()
    source = (ROOT / "packages/GalleryUI/Sources/GalleryUI/GalleryRecognition.swift").read_text()
    start = source.index("    @available(macOS 10.15, *)\n    public func canTranslate()")
    end = source.index("    @available(macOS 10.15, *)\n    private var selectorView", start)
    methods = source[start:end].replace("RegramPreferences.shared", "fixturePreferences")
    observer = declaration(source, "settingsObserver = NotificationCenter.default.addObserver").replace("RegramPreferences.shared", "fixturePreferences")
    fixture = (HERE / "LogicChecks.swift").read_text().replace("__GALLERY_METHODS__", methods).replace("__SETTINGS_OBSERVER__", observer)
    rgg = (ROOT / "packages/RegramServices/Sources/RegramServices/RGGTranslate.swift").read_text()
    sources = [rgg.split("private let rgTranslateSessionConfiguration", 1)[0], declaration(rgg, "func rgTranslateSequentially("), (ROOT / "packages/RegramServices/Sources/RegramServices/RGLLMTranslate.swift").read_text().split("private final class RGTranslationRequestLimiter", 1)[0], (ROOT / "packages/RegramServices/Sources/RegramServices/RegramChatTranslationPolicy.swift").read_text(), (ROOT / "packages/RegramServices/Sources/RegramServices/RegramServiceConfiguration.swift").read_text().split("public func regramSTTConfiguration", 1)[0], (ROOT / "packages/RegramServices/Sources/RegramServices/RegramImageTranslation.swift").read_text()]
    support = (ROOT / "packages/RegramServices/Sources/RegramServices/RegramTaskSupport.swift").read_text()
    sources.append(declaration(support, "public struct RegramLLMContextMessage") + "\n" + declaration(support, "public enum RegramLLMContextPolicy"))
    sources.append((ROOT / "packages/RegramServices/Sources/RegramServices/RegramChatLanguagePolicy.swift").read_text())
    with tempfile.TemporaryDirectory(prefix="regram-image-translation-checks-") as temporary:
        directory = Path(temporary)
        shutil.copytree(args.products / "RegramCore_RegramCore.bundle", directory / "RegramCore_RegramCore.bundle")
        logic = directory / "logic.swift"
        logic.write_text(fixture + "\n" + "\n".join(sources))
        binary = directory / "logic-checks"
        subprocess.run(["xcrun", "swiftc", "-O", "-D", "STABLE", "-parse-as-library", "-target", "arm64-apple-macos12.0", "-I", str(args.products), str(args.products / "RegramCore.o"), str(args.products / "SwiftSignalKit.o"), str(logic), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True, timeout=45)
        types = (ROOT / "packages/TextRecognizing/Sources/TextRecognizing/TextRecognizing.swift").read_text().split("    public static func recognize(", 1)[0] + "}\n"
        types = "\n".join(line for line in types.splitlines() if not line.startswith("import "))
        overlay = (ROOT / "packages/TextRecognizing/Sources/TextRecognizing/ImageTextSelector.swift").read_text().split("        private var trackingArea:", 1)[0] + "    }\n}\n"
        native = directory / "native.swift"
        native.write_text("import Cocoa\nimport SwiftSignalKit\nimport TGUIKit\n" + types + "\n" + (ROOT / "packages/TextRecognizing/Sources/TextRecognizing/DrawRects.swift").read_text() + "\n" + overlay + "\n" + (ROOT / "packages/TextRecognizing/Tests/TextRecognizingTests/TestBootstrap.swift").read_text() + "\n" + (HERE / "NativeOverlayChecks.swift").read_text())
        flags = ["xcrun", "swiftc", "-O", "-D", "STABLE", "-target", "arm64-apple-macos12.0", "-I", str(args.products), "-I", str(args.products / "include"), "-F", str(args.products)]
        for path in (args.products.parents[1] / "Intermediates.noindex/GeneratedModuleMaps").glob("*.modulemap"):
            flags += ["-Xcc", "-fmodule-map-file=" + str(path)]
        objects = [args.products / (name + ".o") for name in ["SwiftSignalKit", "TGUIKit", "ColorPalette", "Colors", "Strings", "KeyboardKey", "ObjcUtils"]]
        native_binary = directory / "native-checks"
        subprocess.run(flags + [str(path) for path in objects] + [str(native), "-o", str(native_binary)], check=True)
        subprocess.run([str(native_binary)], check=True, timeout=20)
        pipeline_start = source.index("            let image: Signal<TextRecognizing.Result?, TextRecognizing.Error>")
        pipeline_end = source.index("            loadedDisposable.set(", pipeline_start)
        pipeline = source[pipeline_start:pipeline_end]
        boundary = "|> map(Optional.init) |> deliverOnMainQueue"
        if pipeline.count(boundary) != 1:
            raise RuntimeError("Review the changed OCR inner delivery boundary")
        ocr_fixture = (HERE / "OCRDeliveryChecks.swift").read_text()
        for name, implementation, arguments in [("ocr", pipeline, []), ("ocr-previous", pipeline.replace(boundary, "|> map(Optional.init)"), ["--expect-stale"])]:
            ocr_source = directory / (name + ".swift")
            ocr_source.write_text(ocr_fixture.replace("__OCR_PIPELINE__", implementation))
            ocr_binary = directory / name
            subprocess.run(["xcrun", "swiftc", "-O", "-target", "arm64-apple-macos12.0", "-I", str(args.products), str(args.products / "SwiftSignalKit.o"), str(ocr_source), "-o", str(ocr_binary)], check=True)
            subprocess.run([str(ocr_binary)] + arguments, check=True, timeout=10)


if __name__ == "__main__":
    main()
