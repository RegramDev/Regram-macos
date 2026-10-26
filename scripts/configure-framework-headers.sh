#!/bin/bash
set -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." >/dev/null && pwd )"

DIRECTORY_PAIRS=(
    "${SCRIPT_DIR}/../core-xprojects/libopus/build/libopus/include,${SCRIPT_DIR}/../submodules/telegram-ios/submodules/OpusBinding/SharedHeaders/libopus/include"
    "${SCRIPT_DIR}/../core-xprojects/ffmpeg/build/ffmpeg/include,${SCRIPT_DIR}/../submodules/telegram-ios/submodules/FFMpegBinding/SharedHeaders/ffmpeg/include"
    "${SCRIPT_DIR}/../core-xprojects/webrtc/build/src,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/webrtc"
    "${SCRIPT_DIR}/../core-xprojects/openssl/build/openssl/include,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/openssl/include"
    "${SCRIPT_DIR}/../core-xprojects/libopus/build/libopus/include,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/libopus/include"
    "${SCRIPT_DIR}/../core-xprojects/ffmpeg/build/ffmpeg/include,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/ffmpeg/include"
    "${SCRIPT_DIR}/../submodules/telegram-ios/third-party/rnnoise/PublicHeaders,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/rnoise"
    "${SCRIPT_DIR}/../core-xprojects/libwebp/build/libwebp/include,${SCRIPT_DIR}/../submodules/libwebp/SharedHeaders/libwebp/include"
    "${SCRIPT_DIR}/../core-xprojects/openssl/build/openssl/include,${SCRIPT_DIR}/../submodules/telegram-ios/submodules/OpenSSLEncryptionProvider/SharedHeaders/openssl/include"
    "${SCRIPT_DIR}/../submodules/telegram-ios/submodules/EncryptionProvider/PublicHeaders,${SCRIPT_DIR}/../submodules/telegram-ios/submodules/OpenSSLEncryptionProvider/SharedHeaders/EncryptionProvider"
    "${SCRIPT_DIR}/../core-xprojects/Mozjpeg/build,${SCRIPT_DIR}/../submodules/Mozjpeg/SharedHeaders/libmozjpeg"
    "${SCRIPT_DIR}/../submodules/telegram-ios/third-party/mozjpeg/mozjpeg,${SCRIPT_DIR}/../submodules/Mozjpeg/SharedHeaders/ios-mozjpeg"
)


for pair in "${DIRECTORY_PAIRS[@]}"; do
    IFS=',' read -r SOURCE_DIR DEST_DIR <<< "$pair"
    sh "$SCRIPT_DIR/sync-headers.sh" "$SOURCE_DIR" "$DEST_DIR"
done

sh "$SCRIPT_DIR/sync-headers.sh" \
    "$ROOT_DIR/submodules/telegram-ios/third-party/td/td" \
    "$ROOT_DIR/submodules/telegram-ios/third-party/td/TdBinding/SharedHeaders/td"
