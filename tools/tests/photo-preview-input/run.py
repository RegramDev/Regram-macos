import argparse
import hashlib
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
INPUT = ROOT / "packages/InputView/Sources/InputView"
MEDIA = ROOT / "packages/TelegramMediaUtils/Sources/TelegramMediaUtils/MediaUtils.swift"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--derived", type=Path, default=Path.home() / "Library/Caches/RegramReleaseDerivedData-arm64")
    parser.add_argument("--output", type=Path, default=Path("/tmp/regram-photo-preview-input"))
    parser.add_argument("--source-ref")
    parser.add_argument("--architecture", choices=["arm64", "x86_64"], default="arm64")
    parser.add_argument("--input-methods-only", action="store_true")
    options = parser.parse_args()
    output = options.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    products = options.derived / "Build/Products/Release"
    intermediates = options.derived / "Build/Intermediates.noindex"
    architecture = options.architecture
    bundle = output / "PhotoInputChecks.app/Contents"
    executable = bundle / "MacOS/PhotoInputChecks"
    executable.parent.mkdir(parents=True, exist_ok=True)
    (bundle / "Resources").mkdir(exist_ok=True)
    (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "local.regram.PhotoInputChecks", "CFBundleExecutable": executable.name, "CFBundleName": "Photo Input Checks", "CFBundlePackageType": "APPL", "LSUIElement": True}))
    shutil.copy2("/Applications/Regram.app/Contents/Resources/Assets.car", bundle / "Resources/Assets.car")

    def source(path):
        if options.source_ref:
            return subprocess.check_output(["git", "show", f"{options.source_ref}:{path.relative_to(ROOT)}"], cwd=ROOT, text=True)
        return path.read_text()

    inputs = []
    hashes = []
    for path in sorted(INPUT.glob("*.swift")):
        text = source(path)
        destination = output / path.name
        destination.write_text(text)
        inputs.append(destination)
        hashes.append(f"{hashlib.sha256(text.encode()).hexdigest()}  {path.relative_to(ROOT)}")
    media = source(MEDIA)
    function = media[media.index("public func chatMessagePhoto(account:"):media.index("public func chatMessageWebFilePhoto(")]
    renderer = function[function.index("        return ImageDataTransformation"):function.rindex("\n    }\n}")]
    rendering = output / "PhotoRendering.swift"
    rendering.write_text("import AppKit\nimport ImageIO\nimport TGUIKit\nimport TelegramMediaUtils\nimport TelegramTheme\nimport FastBlur\nfunc regressionPhoto(data: ImageRenderData, scale: CGFloat) -> ImageDataTransformation {\n" + renderer + "\n}\n")
    progressive = media[media.index("public func chatMessagePhotoDatas("):media.index("    if let smallestRepresentation = firstImageRepresentation(")]
    progressive = progressive.replace("public func chatMessagePhotoDatas(", "func regressionPhotoDatas(", 1).replace("postbox: Postbox", "postbox: FixturePostbox", 1)
    emission = media[media.index("private final class ProgressiveEmissionState"):media.index("public func chatMessagePhotoDatas(")]
    datas = output / "PhotoData.swift"
    datas.write_text("import AppKit\nimport Postbox\nimport TelegramCore\nimport SwiftSignalKit\nimport TGUIKit\nimport TelegramMediaUtils\nimport TelegramUtils\nstruct FixturePostbox { let mediaBox: MediaBox }\n" + emission + progressive + "\nreturn .complete()\n}\n")
    hashes.append(f"{hashlib.sha256(media.encode()).hexdigest()}  {MEDIA.relative_to(ROOT)}")
    (output / "source-hashes.txt").write_text("\n".join(hashes) + "\n")

    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    args = ["xcrun", "swiftc", "-O", "-module-name", "InputView", "-parse-as-library", "-D", "SWIFT_PACKAGE", "-D", "STABLE", "-target", f"{architecture}-apple-macos12.0", "-sdk", sdk, "-F", str(products), "-I", str(products), "-I", str(products / "include")]
    for module_map in sorted((intermediates / "GeneratedModuleMaps").glob("*.modulemap")):
        args += ["-Xcc", "-fmodule-map-file=" + str(module_map)]
    headers = [ROOT / "submodules/tgcalls/macos/PublicHeaders", ROOT / "submodules/telegram-ios/submodules/TelegramApi/ObjC/PublicHeaders"]
    for package in sorted((ROOT / "submodules/telegram-ios/submodules").iterdir()):
        headers += [package / suffix for suffix in ["PublicHeaders", "Public", "Sources/PublicHeaders"] if (package / suffix).is_dir()]
    for header in headers:
        args += ["-Xcc", "-I" + str(header)]
    link_file = intermediates / f"Telegram.build/Release/Telegram.build/Objects-normal/{architecture}/Regram.LinkFileList"
    objects = [path for path in link_file.read_text().splitlines() if str(products) + "/" in path and path.endswith(".o") and not Path(path).stem.endswith("Share") and Path(path).stem != "InputView"]
    object_list = output / "Objects.LinkFileList"
    object_list.write_text("\n".join(objects) + "\n")
    args += [str(path) for path in inputs] + [str(rendering), str(datas), str(HERE / "NativeChecks.swift"), "-Xlinker", "-filelist", "-Xlinker", str(object_list), "-Xlinker", "-dead_strip"]
    for path in ["libvpx/build/libvpx/lib", "ffmpeg/build/ffmpeg/lib", "libopus/build/libopus/lib", "libwebp/build/libwebp/lib", "Mozjpeg/build", "openssl/build/openssl/lib", "webrtc/build/webrtc", "OpenH264/build/output/lib", "dav1d/build/dav1d/lib", "tde2e/build/tde2e/lib", "tlottie/build"]:
        args += ["-L", str(ROOT / "core-xprojects" / path)]
    args += ["-L", str(products), "-F", str(ROOT / "submodules"), "-F", str(ROOT / "submodules/AppCenter"), "-Xlinker", "-rpath", "-Xlinker", str(products), "-Xlinker", "-rpath", "-Xlinker", str(ROOT / "submodules")]
    for library in ["c++", "tlottie", "resolv", "z", "mtproto_engine_ffi", "wallet_engine", "tdutils", "tde2e", "openh264", "avutil", "webpdecoder", "bz2.1.0", "crypto", "avformat", "webp", "swresample", "webpdemux", "opus", "iconv", "ssl", "dav1d", "jpeg", "sharpyuv", "avcodec", "vpx", "mac_framework_objc_static"]:
        args.append("-l" + library)
    for framework in ["AppKit", "Foundation", "Security", "Speech", "AuthenticationServices", "CodeSyntax", "SceneKit", "CoreMediaIO", "Carbon", "WebKit", "MetalKit", "Metal", "CoreSpotlight", "RLottie", "CoreMedia", "Sparkle", "Contacts", "QuartzCore", "VideoToolbox", "Accelerate", "EventKit", "LocalAuthentication", "CoreServices", "CoreVideo", "OpenGL", "IOKit", "QuickLook", "JavaScriptCore", "MapKit", "Quartz", "AVFoundation", "MediaPlayer"]:
        args += ["-framework", framework]
    args += ["-o", str(executable)]
    (output / "compile-command.txt").write_text(shlex.join(args))
    with (output / "compile.log").open("w") as log:
        result = subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    print(f"native compile exit={result.returncode}; log={output / 'compile.log'}", flush=True)
    if result.returncode:
        return result.returncode
    with (output / "run.log").open("w") as log:
        result = subprocess.run([str(executable), str(output)] + (["--input-methods-only"] if options.input_methods_only else []), cwd=output, stdout=log, stderr=subprocess.STDOUT)
    print((output / "run.log").read_text()[-5000:])
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
