from pathlib import Path
import subprocess
import tempfile


submodules = Path(__file__).resolve().parents[3] / "submodules/telegram-ios/submodules"
postbox = submodules / "Postbox/Sources"
core = submodules / "TelegramCore/Sources"
mur_mur = submodules / "MurMurHash32"
headers = mur_mur / "PublicHeaders"

with tempfile.TemporaryDirectory(prefix="regram-archive-placement-") as directory:
    scratch = Path(directory)
    header = headers / "MurMurHash32/MurMurHash32.h"
    (scratch / "module.modulemap").write_text(f'module MurMurHash32 {{ header "{header}" export * }}\n')
    library = scratch / "libMurMurHash32.dylib"
    subprocess.run([
        "xcrun", "clang", "-dynamiclib", "-fobjc-arc", "-framework", "Foundation",
        "-I", str(headers), str(mur_mur / "Sources/MurMurHash32.m"), "-o", str(library),
    ], check=True)
    sources = [
        core / "State/RegramChatListPlacement.swift",
        core / "SyncCore/SyncCore_SynchronizeGroupedPeersOperation.swift",
    ]
    local_sources = []
    for source in sources:
        local = scratch / source.name
        local.write_text(source.read_text().replace("import Postbox\n", "", 1))
        local_sources.append(local)
    executable = scratch / "ArchivePlacementTests"
    subprocess.run([
        "xcrun", "swiftc", "-O", "-DSTABLE", "-swift-version", "5", "-parse-as-library",
        "-I", str(scratch), "-L", str(scratch), "-lMurMurHash32", "-Xlinker", "-rpath", "-Xlinker", str(scratch),
        *map(str, local_sources), str(Path(__file__).with_name("ArchivePlacementTests.swift")),
        str(postbox / "Coding.swift"), str(postbox / "PreferencesEntry.swift"),
        str(postbox / "PeerGroup.swift"), str(postbox / "PeerChatListInclusion.swift"),
        *map(str, sorted((postbox / "Utils").rglob("*.swift"))), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)
