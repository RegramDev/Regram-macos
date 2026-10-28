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
    parser.add_argument("--output", type=Path, default=Path("/tmp/regram-native-ui"))
    parser.add_argument("--compile-only", action="store_true")
    parser.add_argument("--search-only", action="store_true")
    parser.add_argument("--search-navigation-only", action="store_true")
    parser.add_argument("--page-builder", type=Path, default=ROOT / "packages/RegramUI/Sources/RegramUI/RegramPageBuilder.swift")
    options = parser.parse_args()
    products = options.derived / "Build/Products/Release"
    intermediates = options.derived / "Build/Intermediates.noindex"
    output = options.output
    output.mkdir(parents=True, exist_ok=True)
    (output / "report.json").unlink(missing_ok=True)
    bundle = output / "NativeUIChecks.app/Contents"
    resources = bundle / "Resources"
    executable = bundle / "MacOS/native-ui-checks"
    executable.parent.mkdir(parents=True, exist_ok=True)
    resources.mkdir(parents=True, exist_ok=True)
    (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "local.regram.NativeUIChecks", "CFBundleExecutable": executable.name, "CFBundleName": "Native UI Checks", "CFBundlePackageType": "APPL", "LSUIElement": True}))
    shutil.copyfile(Path("/Applications/Regram.app/Contents/Resources/Assets.car"), resources / "Assets.car")
    generated_assets = intermediates / "Telegram.build/Release/Telegram.build/DerivedSources/GeneratedAssetSymbols.swift"
    assets = output / "GeneratedAssetSymbols.swift"
    assets.write_text(generated_assets.read_text().replace("Foundation.Bundle.module", "Foundation.Bundle.main"))
    account_source = (ROOT / "packages/SettingsUI/Sources/SettingsUI/AccountViewController.swift").read_text()
    factory = declaration(account_source, "private func accountMessageSettingsIcon(")
    navigation_source = ROOT / "Telegram-Mac/app/MainViewController.swift"
    navigation = declaration(navigation_source.read_text(), "private func rebuildNavigationTabs()")
    navigation = navigation.split("rebuildingNavigation = true", 1)[1].split("previousIndex = target", 1)[0].replace("regramVisibleTabs = visible", "")
    navigation_controller_source = ROOT / "packages/RegramUI/Sources/RegramUI/RegramNavigationController.swift"
    navigation_switches = declaration(navigation_controller_source.read_text(), "private func regramConfigureNavigationSwitches(").replace("private func", "func", 1)
    glyphs = re.findall(r"icon: accountMessageSettingsIcon\((.*?)\), type:", account_source)
    if len(glyphs) != 2:
        raise RuntimeError("Review the two account icon call sites")
    theme_hooks = (ROOT / "Telegram-Mac/packages-integration/hooks/TelegramThemeHooksInstall.swift").read_text()
    image_hook = declaration(theme_hooks, "private func themeHookImage(")
    extracted = output / "ProductionIconFunctions.swift"
    bookmarks = (ROOT / "packages/RegramUI/Sources/RegramUI/RegramBookmarksController.swift").read_text()
    reset = declaration(bookmarks, "clearSearch = { [weak controller] in")
    unflipped = glyphs[0].replace(", flipVertical: true", "").replace("flipVertical: true", "")
    extracted.write_text("import Cocoa\nimport TGUIKit\nimport GeneralRows\nimport InputDataUI\nimport SwiftSignalKit\nimport TelegramTheme\n" + factory + "\n" + image_hook + "\nfunc savedSettingsIcon() -> CGImage? { accountMessageSettingsIcon(" + glyphs[0] + ") }\nfunc bookmarkSettingsIcon() -> CGImage? { accountMessageSettingsIcon(" + glyphs[1] + ") }\nfunc previousSavedSettingsIcon() -> CGImage? { accountMessageSettingsIcon(" + unflipped + ") }\nfunc nativeThemeImage(_ image: TelegramThemeImage) -> NSImage { themeHookImage(image) }\nprivate let bookmarkSearchId = InputDataIdentifier(\"bookmarks_search\")\nfunc resetBookmarkSearch(_ controller: InputDataController) { let clearSearch: () -> Void\n" + reset + "\nclearSearch() }\n")
    with extracted.open("a") as source:
        source.write("import RegramCore\nfunc rebuildNativeBottomBar(_ tabController: TabBarController, tabs regramTabs: [RegramBottomBarItemId: TabItem], visible: [RegramBottomBarItemId], selected: RegramBottomBarItemId) {\n" + navigation + "\n}\n")
        source.write(navigation_switches + "\n")
        appearance_source = ROOT / "Telegram-Mac/packages-integration/bridges/RegramAppearanceIntegration.swift"
        source.write("import ColorPalette\nimport ThemeSettings\nimport Postbox\nimport TelegramCore\n")
        source.write(declaration(appearance_source.read_text(), "func regramRepairedThemePalette(") + "\n")
        source.write(declaration(appearance_source.read_text(), "func bindRegramThemeRepairs(") + "\n")
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    args = ["xcrun", "swiftc", "-module-name", "RegramNativeUIChecks", "-parse-as-library", "-D", "SWIFT_PACKAGE", "-D", "STABLE", "-target", "arm64-apple-macos12.0", "-sdk", sdk, "-F", str(products), "-I", str(products), "-I", str(products / "include")]
    for module_map in sorted((intermediates / "GeneratedModuleMaps").glob("*.modulemap")):
        args += ["-Xcc", "-fmodule-map-file=" + str(module_map)]
    headers = [ROOT / "submodules/tgcalls/macos/PublicHeaders", ROOT / "submodules/telegram-ios/submodules/TelegramApi/ObjC/PublicHeaders"]
    for package in sorted((ROOT / "submodules/telegram-ios/submodules").iterdir()):
        headers += [package / suffix for suffix in ["PublicHeaders", "Public", "Sources/PublicHeaders"] if (package / suffix).is_dir()]
    for header in headers:
        args += ["-Xcc", "-I" + str(header)]
    link_file = intermediates / "Telegram.build/Release/Telegram.build/Objects-normal/arm64/Regram.LinkFileList"
    objects = [path for path in link_file.read_text().splitlines() if str(products) + "/" in path and path.endswith(".o") and not Path(path).stem.endswith("Share")]
    (output / "Objects.LinkFileList").write_text("\n".join(objects) + "\n")
    args += [str(HERE / "NativeUIChecks.swift"), str(extracted), str(assets), str(options.page_builder), str(ROOT / "packages/RegramUI/Sources/RegramUI/RegramSelectionRows.swift"), "-Xlinker", "-filelist", "-Xlinker", str(output / "Objects.LinkFileList"), "-Xlinker", "-dead_strip"]
    native_paths = ["libvpx/build/libvpx/lib", "ffmpeg/build/ffmpeg/lib", "libopus/build/libopus/lib", "libwebp/build/libwebp/lib", "Mozjpeg/build", "openssl/build/openssl/lib", "webrtc/build/webrtc", "OpenH264/build/output/lib", "dav1d/build/dav1d/lib", "tde2e/build/tde2e/lib", "tlottie/build"]
    for path in native_paths:
        args += ["-L", str(ROOT / "core-xprojects" / path)]
    args += ["-L", str(products), "-F", str(ROOT / "submodules"), "-F", str(ROOT / "submodules/AppCenter"), "-Xlinker", "-rpath", "-Xlinker", str(products), "-Xlinker", "-rpath", "-Xlinker", str(ROOT / "submodules")]
    for library in ["c++", "tlottie", "resolv", "z", "mtproto_engine_ffi", "wallet_engine", "tdutils", "tde2e", "openh264", "avutil", "webpdecoder", "bz2.1.0", "crypto", "avformat", "webp", "swresample", "webpdemux", "opus", "iconv", "ssl", "dav1d", "jpeg", "sharpyuv", "avcodec", "vpx", "mac_framework_objc_static"]:
        args.append("-l" + library)
    for framework in ["AppKit", "Foundation", "Security", "Speech", "AuthenticationServices", "CodeSyntax", "SceneKit", "CoreMediaIO", "Carbon", "WebKit", "MetalKit", "Metal", "CoreSpotlight", "RLottie", "CoreMedia", "Sparkle", "Contacts", "QuartzCore", "VideoToolbox", "Accelerate", "EventKit", "LocalAuthentication", "CoreServices", "CoreVideo", "OpenGL", "IOKit", "QuickLook", "JavaScriptCore", "MapKit", "Quartz", "AVFoundation", "MediaPlayer"]:
        args += ["-framework", framework]
    args += ["-o", str(executable)]
    source_files = [options.page_builder, ROOT / "packages/RegramUI/Sources/RegramUI/RegramSelectionRows.swift", ROOT / "packages/SettingsUI/Sources/SettingsUI/AccountViewController.swift", ROOT / "packages/RegramUI/Sources/RegramUI/RegramBookmarksController.swift", navigation_source, navigation_controller_source, appearance_source]
    manifest = {"productionSources": {str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_files}, "accountIconExpressions": glyphs, "cachedObjects": len(objects), "applicationObjectsLinked": False, "shareExtensionObjectsLinked": False, "imageResources": "installed Assets.car", "target": "arm64-apple-macos12.0"}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2))
    (output / "compile-command.txt").write_text(shlex.join(args))
    with (output / "compile.log").open("w") as log:
        result = subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    print(f"native UI compile exit={result.returncode}; objects={len(objects)}; log={output / 'compile.log'}", flush=True)
    if result.returncode:
        raise SystemExit(result.returncode)
    if not options.compile_only:
        subprocess.run([str(executable), str(output)] + (["--search-only"] if options.search_only else []) + (["--search-navigation-only"] if options.search_navigation_only else []), check=True, cwd=output)


if __name__ == "__main__":
    main()
