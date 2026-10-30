from pathlib import Path
import argparse
import subprocess


ROOT = Path(__file__).resolve().parents[3]
NATIVE_DIRECTORIES = [
    "libvpx/build/libvpx/lib", "ffmpeg/build/ffmpeg/lib", "libopus/build/libopus/lib",
    "libwebp/build/libwebp/lib", "Mozjpeg/build", "openssl/build/openssl/lib",
    "webrtc/build/webrtc", "OpenH264/build/output/lib", "dav1d/build/dav1d/lib", "tde2e/build/tde2e/lib",
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", choices=["ChatUI", "ChatHistoryModel", "SidebarUI", "GeneralRows", "ChatListUI", "QrStudioUI"], default="ChatUI")
    parser.add_argument("--filter", default="RegramMentionEntityTests|RegramFilteredReadingTests")
    arguments = parser.parse_args()
    command = ["swift", "test", "-c", "release", "-Xswiftc", "-DSTABLE", "--package-path", str(ROOT / "packages" / arguments.package),
               "--scratch-path", str(ROOT / "packages/ChatUI/.build"), "-j", "4", "--filter", arguments.filter]
    for flag in ["-lbz2", "-liconv"]:
        command.extend(["-Xlinker", flag])
    for directory in NATIVE_DIRECTORIES:
        libraries = sorted((ROOT / "core-xprojects" / directory).glob("*.a"))
        if not libraries:
            raise FileNotFoundError(f"Missing native libraries: {directory}")
        for library in libraries:
            command.extend(["-Xlinker", str(library)])
    if arguments.package in ["ChatHistoryModel", "SidebarUI"]:
        rnnoise = ROOT / "packages/ChatUI/.build/out/Products/Release/rnoise.o"
        if not rnnoise.is_file():
            raise FileNotFoundError("Run the ChatUI regressions first to build the shared RNNoise object")
        command.extend(["-Xlinker", str(rnnoise)])
    return subprocess.run(command, cwd=ROOT).returncode


if __name__ == "__main__":
    raise SystemExit(main())
