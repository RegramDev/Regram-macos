from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shlex
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    cursor = opening + 1
    depth = 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--derived', type=Path, default=Path.home() / 'Library/Caches/RegramReleaseDerivedData-arm64')
    parser.add_argument('--output', type=Path, default=Path('/tmp/regram-folder-switch-checks'))
    parser.add_argument('--source-root', type=Path, default=ROOT)
    parser.add_argument('--negative-control', type=Path)
    parser.add_argument('--negative-layout', type=Path)
    options = parser.parse_args()
    output = options.output
    output.mkdir(parents=True, exist_ok=True)
    products = options.derived / 'Build/Products/Release'
    intermediates = options.derived / 'Build/Intermediates.noindex'
    chat = options.source_root / 'packages/ChatListUI/Sources/ChatListUI'
    controller = (chat / 'ChatListController.swift').read_text()
    peers = (chat / 'PeersListController.swift').read_text()
    reveal = (chat / 'ChatListRevealItem.swift').read_text()
    bridge = (options.source_root / 'Telegram-Mac/packages-integration/bridges/SidebarUIIntegration.swift').read_text()
    route_source = peers
    archive_source = controller
    geometry_source = peers
    layout_source = reveal
    if options.negative_control:
        route_source = (options.negative_control / 'PeersListController.swift').read_text()
        geometry_source = route_source
        archive_source = (options.negative_control / 'ChatListController.swift').read_text()
    if options.negative_layout:
        layout_source = options.negative_layout.read_text()
    route = declaration(route_source, 'setupFilter: { [weak self] filter in').split(': ', 1)[1]
    archive_start = archive_source.index('        let regramArchiveGroup: Signal<EngineChatList.GroupItem?, NoError>')
    archive_end = archive_source.index('        let regramAppearance', archive_start)
    segment_start = reveal.index('        let previousItems = Dictionary(uniqueKeysWithValues: segmentItems.map')
    segment_end = reveal.index('        guard !items.isEmpty', segment_start)
    replacements = {
        'PRODUCTION_FILTER_DATA': declaration(controller, 'public struct FilterData : Equatable').replace('public ', ''),
        'PRODUCTION_BASE_UPDATE': declaration(peers, '    open func updateState(_ f:').replace('open ', ''),
        'PRODUCTION_BASE_SELECT': declaration(peers, '    open func selectFilter(').replace('open ', ''),
        'PRODUCTION_CHAT_SELECT': declaration(controller, '    public override func selectFilter(').replace('public ', ''),
        'PRODUCTION_CHAT_UPDATE': declaration(controller, '    public func updateFilter(').replace('public ', ''),
        'PRODUCTION_TOP_ROUTE': route,
        'PRODUCTION_SIDEBAR_ROUTE': declaration(bridge, 'func navigateToChatListFilter('),
        'PRODUCTION_ARCHIVE': archive_source[archive_start:archive_end] + '\nreturn regramArchiveGroup',
        'PRODUCTION_HEADER_APPLY': declaration(peers, '        if let item = self.foldersItem {'),
        'PRODUCTION_HEADER_GEOMETRY': declaration(geometry_source, '        if let foldersItem = foldersItem, let view = foldersView {'),
        'PRODUCTION_HEADER_LAYOUT': declaration(layout_source, '    public override func layout()').replace('public ', ''),
        'PRODUCTION_SEGMENT_BINDING': reveal[segment_start:segment_end],
    }
    fixture = (HERE / 'FolderSwitchChecks.swift').read_text()
    for marker, value in replacements.items():
        if fixture.count(marker) != 1:
            raise RuntimeError('Invalid fixture marker ' + marker)
        fixture = fixture.replace(marker, value)
    source = output / 'ProductionFolderSwitchChecks.swift'
    source.write_text(fixture)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    args = ['xcrun', 'swiftc', '-module-name', 'FolderSwitchChecks', '-parse-as-library', '-D', 'SWIFT_PACKAGE', '-D', 'STABLE', '-target', 'arm64-apple-macos12.0', '-sdk', sdk, '-F', str(products), '-I', str(products), '-I', str(products / 'include')]
    for module_map in sorted((intermediates / 'GeneratedModuleMaps').glob('*.modulemap')):
        args += ['-Xcc', '-fmodule-map-file=' + str(module_map)]
    headers = [ROOT / 'submodules/tgcalls/macos/PublicHeaders', ROOT / 'submodules/telegram-ios/submodules/TelegramApi/ObjC/PublicHeaders']
    for package in sorted((ROOT / 'submodules/telegram-ios/submodules').iterdir()):
        headers += [package / suffix for suffix in ['PublicHeaders', 'Public', 'Sources/PublicHeaders'] if (package / suffix).is_dir()]
    for header in headers:
        args += ['-Xcc', '-I' + str(header)]
    link_file = intermediates / 'Telegram.build/Release/Telegram.build/Objects-normal/arm64/Regram.LinkFileList'
    objects = [path for path in link_file.read_text().splitlines() if str(products) + '/' in path and path.endswith('.o') and not Path(path).stem.endswith('Share')]
    (output / 'Objects.LinkFileList').write_text('\n'.join(objects) + '\n')
    args += [str(source), '-Xlinker', '-filelist', '-Xlinker', str(output / 'Objects.LinkFileList'), '-Xlinker', '-dead_strip']
    for path in ['libvpx/build/libvpx/lib', 'ffmpeg/build/ffmpeg/lib', 'libopus/build/libopus/lib', 'libwebp/build/libwebp/lib', 'Mozjpeg/build', 'openssl/build/openssl/lib', 'webrtc/build/webrtc', 'OpenH264/build/output/lib', 'dav1d/build/dav1d/lib', 'tde2e/build/tde2e/lib', 'tlottie/build']:
        args += ['-L', str(ROOT / 'core-xprojects' / path)]
    args += ['-L', str(products), '-F', str(ROOT / 'submodules'), '-F', str(ROOT / 'submodules/AppCenter'), '-Xlinker', '-rpath', '-Xlinker', str(products), '-Xlinker', '-rpath', '-Xlinker', str(ROOT / 'submodules')]
    for library in ['c++', 'tlottie', 'resolv', 'z', 'mtproto_engine_ffi', 'wallet_engine', 'tdutils', 'tde2e', 'openh264', 'avutil', 'webpdecoder', 'bz2.1.0', 'crypto', 'avformat', 'webp', 'swresample', 'webpdemux', 'opus', 'iconv', 'ssl', 'dav1d', 'jpeg', 'sharpyuv', 'avcodec', 'vpx', 'mac_framework_objc_static']:
        args.append('-l' + library)
    for framework in ['AppKit', 'Foundation', 'Security', 'Speech', 'AuthenticationServices', 'CodeSyntax', 'SceneKit', 'CoreMediaIO', 'Carbon', 'WebKit', 'MetalKit', 'Metal', 'CoreSpotlight', 'RLottie', 'CoreMedia', 'Sparkle', 'Contacts', 'QuartzCore', 'VideoToolbox', 'Accelerate', 'EventKit', 'LocalAuthentication', 'CoreServices', 'CoreVideo', 'OpenGL', 'IOKit', 'QuickLook', 'JavaScriptCore', 'MapKit', 'Quartz', 'AVFoundation', 'MediaPlayer']:
        args += ['-framework', framework]
    bundle = output / 'FolderSwitchChecks.app/Contents'
    binary = bundle / 'MacOS/folder-switch-checks'
    binary.parent.mkdir(parents=True, exist_ok=True)
    resources = bundle / 'Resources'
    resources.mkdir(parents=True, exist_ok=True)
    (bundle / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'local.regram.FolderSwitchChecks', 'CFBundleExecutable': binary.name, 'CFBundleName': 'Folder Switch Checks', 'CFBundlePackageType': 'APPL', 'LSUIElement': True}))
    shutil.copyfile(Path('/Applications/Regram.app/Contents/Resources/Assets.car'), resources / 'Assets.car')
    args += ['-o', str(binary)]
    (output / 'compile-command.txt').write_text(shlex.join(args))
    (output / 'manifest.json').write_text(json.dumps({'productionSources': {str(path.relative_to(options.source_root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [chat / 'ChatListController.swift', chat / 'PeersListController.swift', chat / 'ChatListRevealItem.swift', options.source_root / 'Telegram-Mac/packages-integration/bridges/SidebarUIIntegration.swift']}, 'nativeScrollableSegmentView': True, 'realSwiftSignalKit': True, 'appObjectsLinked': False, 'sourceExtractionHashes': {name: hashlib.sha256(value.encode()).hexdigest() for name, value in replacements.items()}, 'negativeControl': str(options.negative_control) if options.negative_control else None, 'negativeLayout': str(options.negative_layout) if options.negative_layout else None}, indent=2))
    with (output / 'compile.log').open('w') as log:
        result = subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    print(f'folder switch compile exit={result.returncode}; log={output / "compile.log"}', flush=True)
    if result.returncode:
        raise SystemExit(result.returncode)
    raise SystemExit(subprocess.run([str(binary), str(output)], cwd=output).returncode)


if __name__ == '__main__':
    main()
