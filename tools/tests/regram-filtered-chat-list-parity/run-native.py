#!/usr/bin/env python3
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--derived-data', type=Path, default=Path.home() / 'Library/Caches/RegramReleaseDerivedData-arm64')
options = parser.parse_args()
build = options.derived_data / 'Build'
products = build / 'Products/Release'
maps = build / 'Intermediates.noindex/GeneratedModuleMaps'
policy = (ROOT / 'packages/ChatListUI/Sources/ChatListUI/RegramFilteredChatListPolicy.swift').read_text()


def declaration(anchor):
    start = policy.index(anchor)
    opening = policy.index('{', start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (policy[cursor] == '{') - (policy[cursor] == '}')
        cursor += 1
    return policy[start:cursor]


production = '\n'.join(declaration(anchor) for anchor in ['struct RegramChatListSourceMessageKey:', 'func regramChatListSourceKeys(', 'struct RegramChatListUnreadSnapshot:', 'func regramChatListCanReadHiddenUnread('])
modules = ['Crc32', 'CryptoUtils', 'DarwinDirStat', 'MurMurHash32', 'StringTransliteration', 'sqlcipher']
objects = ['Postbox', 'ManagedFile', 'RangeSet', 'SwiftSignalKit', *modules]
with tempfile.TemporaryDirectory(prefix='regram-filtered-chat-list-native-') as directory:
    work = Path(directory)
    source = work / 'ProductionValidator.swift'
    source.write_text('import Foundation\nimport Postbox\n' + production)
    binary = work / 'checks'
    command = ['xcrun', 'swiftc', '-swift-version', '5', '-DSTABLE', '-warnings-as-errors', '-parse-as-library', '-target', 'arm64-apple-macosx12.0', '-I', str(products), '-F', str(products), '-I', str(products / 'include')]
    for module in modules:
        modulemap = maps / (module + '.modulemap')
        command += ['-Xcc', '-fmodule-map-file=' + str(modulemap)]
        for header in re.findall(r'header "([^"]+)"', modulemap.read_text()):
            command += ['-I', str(Path(header).parent), '-I', str(Path(header).parent.parent)]
    command += [str(source), str(HERE / 'NativePostbox.swift'), *[str(products / (name + '.o')) for name in objects], '-L', str(ROOT / 'core-xprojects/openssl/build/openssl/lib'), '-lcrypto', '-lssl', '-lz', '-lc++', '-framework', 'Foundation', '-framework', 'Security', '-o', str(binary)]
    subprocess.run(command, cwd=ROOT, check=True)
    subprocess.run([str(binary)], cwd=ROOT, check=True, timeout=45)
