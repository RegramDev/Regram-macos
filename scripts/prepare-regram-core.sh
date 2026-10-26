#!/bin/bash
set -euo pipefail

REGRAM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGRAM_CORE_ROOT="$REGRAM_ROOT/submodules/telegram-ios"
REGRAM_PATCH="$REGRAM_ROOT/patches/regram-telegram-core.patch"
REGRAM_EXPECTED_REVISION="fb0e62ba8a147f0821da6aa63c09da7d79a10111"

if [ ! -f "$REGRAM_CORE_ROOT/.git" ] || [ ! -f "$REGRAM_PATCH" ]; then
    echo "Initialize submodules/telegram-ios before preparing the Regram core." >&2
    exit 1
fi

if git -C "$REGRAM_CORE_ROOT" apply --reverse --check "$REGRAM_PATCH" 2>/dev/null; then
    echo "Regram core patch is already applied."
    exit 0
fi

if [ "$(git -C "$REGRAM_CORE_ROOT" rev-parse HEAD)" != "$REGRAM_EXPECTED_REVISION" ]; then
    echo "The Regram core patch requires telegram-ios at $REGRAM_EXPECTED_REVISION." >&2
    exit 1
fi

git -C "$REGRAM_CORE_ROOT" apply --check "$REGRAM_PATCH"
git -C "$REGRAM_CORE_ROOT" apply "$REGRAM_PATCH"
echo "Regram core patch applied."
