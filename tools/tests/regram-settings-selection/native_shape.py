from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re
import shlex
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--derived", type=Path, default=Path.home() / "Library/Caches/RegramReleaseDerivedData-arm64")
    parser.add_argument("--output", type=Path, default=Path("/tmp/regram-settings-selection-native"))
    parser.add_argument("--compile-only", action="store_true")
    options = parser.parse_args()
    products = options.derived / "Build/Products/Release"
    intermediates = options.derived / "Build/Intermediates.noindex"
    output = options.output
    output.mkdir(parents=True, exist_ok=True)
    account_path = ROOT / "packages/SettingsUI/Sources/SettingsUI/AccountViewController.swift"
    account = account_path.read_text()
    start = account.index("    let messageBookmarksEnabled = RegramPreferences.shared.settings")
    entries = account[start:account.index("    entries.append(.whiteSpace", start)]
    preference = 'RegramPreferences.shared.settings(accountId: context.peerId.toInt64())["messageBookmarksEnabled"].bool'
    if entries.count(preference) != 1:
        raise RuntimeError("Review the changed shortcut flag boundary")
    entries = entries.replace(preference, "bookmarksEnabled")
    saved = "entries.append(.savedMessages(index: index, viewType: .singleItem))"
    bookmarks = "entries.append(.bookmarks(index: index, viewType: .singleItem))"
    if entries.count(saved) != 1 or entries.count(bookmarks) != 1:
        raise RuntimeError("Review the current independent shortcut backgrounds")
    previous = entries.replace(saved, "entries.append(.savedMessages(index: index, viewType: messageBookmarksEnabled ? .firstItem : .singleItem))")
    previous = previous.replace(bookmarks, "entries.append(.bookmarks(index: index, viewType: .lastItem))")
    factories = []
    for marker in ["        case let .savedMessages(_, viewType):", "        case let .bookmarks(_, viewType):"]:
        begin = account.index(marker)
        factories.append(account[begin:account.index("        case ", begin + len(marker))])
    insets = [re.search(r"inset: (NSEdgeInsets\(left: [^)]+\))", factory).group(1) for factory in factories]
    if len(set(insets)) != 1 or any("viewType: viewType" not in factory or "customTheme: .initialize(theme, background: .clear)" not in factory for factory in factories):
        raise RuntimeError("Review the native shortcut row factories")
    generated = output / "ProductionShortcutEntries.swift"
    functions = "import Cocoa\nimport GeneralRows\nimport TelegramTheme\n"
    for name, body in [("productionShortcutEntries", entries), ("previousShortcutEntries", previous)]:
        functions += "func " + name + "(bookmarksEnabled: Bool) -> [ShortcutEntry] {\nvar entries: [ShortcutEntry] = []\nvar index = 0\n" + body + "\nreturn entries\n}\n"
    functions += "func productionShortcutInset() -> NSEdgeInsets { " + insets[0] + " }\n"
    hook = (ROOT / "Telegram-Mac/packages-integration/hooks/TelegramThemeHooksInstall.swift").read_text()
    functions += declaration(hook, "private func themeHookImage(")
    functions += "\nfunc nativeThemeImage(_ image: TelegramThemeImage) -> NSImage { themeHookImage(image) }\n"
    generated.write_text(functions)
    contents = output / "SettingsSelectionShape.app/Contents"
    resources = contents / "Resources"
    executable = contents / "MacOS/settings-selection-shape"
    executable.parent.mkdir(parents=True, exist_ok=True)
    resources.mkdir(parents=True, exist_ok=True)
    (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "local.regram.SettingsSelectionShape", "CFBundleExecutable": executable.name, "CFBundleName": "Settings Selection Shape Checks", "CFBundlePackageType": "APPL", "LSUIElement": True}))
    shutil.copyfile(Path("/Applications/Regram.app/Contents/Resources/Assets.car"), resources / "Assets.car")
    symbols = output / "GeneratedAssetSymbols.swift"
    symbols.write_text((intermediates / "Telegram.build/Release/Telegram.build/DerivedSources/GeneratedAssetSymbols.swift").read_text().replace("Foundation.Bundle.module", "Foundation.Bundle.main"))
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    args = ["xcrun", "swiftc", "-module-name", "SettingsSelectionShapeChecks", "-parse-as-library", "-D", "SWIFT_PACKAGE", "-D", "STABLE", "-target", "arm64-apple-macos12.0", "-sdk", sdk, "-F", str(products), "-I", str(products), "-I", str(products / "include")]
    for module_map in sorted((intermediates / "GeneratedModuleMaps").glob("*.modulemap")):
        args += ["-Xcc", "-fmodule-map-file=" + str(module_map)]
    headers = [ROOT / "submodules/tgcalls/macos/PublicHeaders", ROOT / "submodules/telegram-ios/submodules/TelegramApi/ObjC/PublicHeaders"]
    for package in sorted((ROOT / "submodules/telegram-ios/submodules").iterdir()):
        headers += [package / suffix for suffix in ["PublicHeaders", "Public", "Sources/PublicHeaders"] if (package / suffix).is_dir()]
    for header in headers:
        args += ["-Xcc", "-I" + str(header)]
    link_file = intermediates / "Telegram.build/Release/Telegram.build/Objects-normal/arm64/Regram.LinkFileList"
    objects = [path for path in link_file.read_text().splitlines() if str(products) + "/" in path and path.endswith(".o") and not Path(path).stem.endswith("Share")]
    filelist = output / "Objects.LinkFileList"
    filelist.write_text("\n".join(objects) + "\n")
    args += [str(HERE / "NativeSelectionShapeChecks.swift"), str(generated), str(symbols), "-Xlinker", "-filelist", "-Xlinker", str(filelist), "-Xlinker", "-dead_strip"]
    for path in ["libvpx/build/libvpx/lib", "ffmpeg/build/ffmpeg/lib", "libopus/build/libopus/lib", "libwebp/build/libwebp/lib", "Mozjpeg/build", "openssl/build/openssl/lib", "webrtc/build/webrtc", "OpenH264/build/output/lib", "dav1d/build/dav1d/lib", "tde2e/build/tde2e/lib", "tlottie/build"]:
        args += ["-L", str(ROOT / "core-xprojects" / path)]
    args += ["-L", str(products), "-F", str(ROOT / "submodules"), "-F", str(ROOT / "submodules/AppCenter"), "-Xlinker", "-rpath", "-Xlinker", str(products), "-Xlinker", "-rpath", "-Xlinker", str(ROOT / "submodules")]
    for library in ["c++", "tlottie", "resolv", "z", "mtproto_engine_ffi", "wallet_engine", "tdutils", "tde2e", "openh264", "avutil", "webpdecoder", "bz2.1.0", "crypto", "avformat", "webp", "swresample", "webpdemux", "opus", "iconv", "ssl", "dav1d", "jpeg", "sharpyuv", "avcodec", "vpx", "mac_framework_objc_static"]:
        args.append("-l" + library)
    for framework in ["AppKit", "Foundation", "Security", "Speech", "AuthenticationServices", "CodeSyntax", "SceneKit", "CoreMediaIO", "Carbon", "WebKit", "MetalKit", "Metal", "CoreSpotlight", "RLottie", "CoreMedia", "Sparkle", "Contacts", "QuartzCore", "VideoToolbox", "Accelerate", "EventKit", "LocalAuthentication", "CoreServices", "CoreVideo", "OpenGL", "IOKit", "QuickLook", "JavaScriptCore", "MapKit", "Quartz", "AVFoundation", "MediaPlayer"]:
        args += ["-framework", framework]
    args += ["-o", str(executable)]
    (output / "compile-command.txt").write_text(shlex.join(args))
    (output / "manifest.json").write_text(json.dumps({"source": str(account_path), "sha256": hashlib.sha256(account_path.read_bytes()).hexdigest(), "entries": entries, "inset": insets[0], "cachedPackageObjects": len(objects), "applicationObjectsLinked": False, "shareObjectsLinked": False}, indent=2))
    with (output / "compile.log").open("w") as log:
        result = subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print((output / "compile.log").read_text()[-10000:])
        raise SystemExit(result.returncode)
    if options.compile_only:
        return
    with (output / "checks.log").open("w") as log:
        result = subprocess.run([str(executable), str(output)], cwd=output, stdout=log, stderr=subprocess.STDOUT, timeout=30)
    print((output / "checks.log").read_text())
    if result.returncode:
        raise SystemExit(result.returncode)
    with (output / "previous-checks.log").open("w") as log:
        negative = subprocess.run([str(executable), str(output), "--previous-grouping"], cwd=output, stdout=log, stderr=subprocess.STDOUT, timeout=30)
    report = json.loads((output / "previous-report.json").read_text())
    failures = report["failures"]
    if negative.returncode != 1 or not failures or any(not name.endswith(("/four-rounded-corners", "/native-four-corner-mask")) for name in failures) or not all(any(row in name for name in failures) for row in ["Saved Messages", "Bookmarks"]):
        raise RuntimeError("Previous grouping did not fail only the native full-pill checks for both shortcuts")
    print(f"Previous grouping negative control: {len(failures)} native corner failures, geometry/selection and disabled-bookmark row remain correct.")


if __name__ == "__main__":
    main()
