# Regram TelegramCore patch

`regram-telegram-core.patch` applies after `scripts/telegram-ios-macos.patch` on the macOS repository's pinned `telegram-ios` revision `24638bc69bd083981b178dd1e7f921eebbf7fc46`.

Run `bash scripts/prepare-regram-core.sh` after initializing that submodule and before opening the workspace. `scripts/configure_frameworks.sh` also runs it. Repeating it is safe; a conflicting checkout produces an error without overwriting local changes.

The patch contains account-scoped Regram policy hooks, message retention and edit attributes, local overflow pins, transcription provenance, external translation provenance, audio draining for transcription, the two local Swift Package path repairs needed by this checkout, and automatic Metal shader compilation for Xcode 27. It preserves the macOS core's server-message merge and adaptive Rust download scheduling.

Profile music repairs are also included: retryable loading, raw server pagination cursors, generation-checked cache and request ownership, subscription-scoped optimistic changes, and cache/preferences/header updates only after server acceptance. The focused Release/STABLE regression runner is `tools/tests/saved-music-loading/run.py`.

Archive placement adapts Regram iOS's `e8f5b4cd09` fix. It preserves a manual move across pending requests, stale dialog and pin responses, and temporarily hidden community chats. The regression runner is `python3 tools/tests/archive-placement/run.py`.

Feature algorithms and model changes were adapted from Regram iOS at `f61df19a1d19e9821f7adcf5c74cbb23601d1683`, under the repository's GPL license. Update the patch when changing the core submodule; the parent repository does not store its uncommitted files.
