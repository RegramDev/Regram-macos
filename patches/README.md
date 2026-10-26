# Regram TelegramCore patch

`regram-telegram-core.patch` applies to the macOS repository's pinned `telegram-ios` revision `fb0e62ba8a147f0821da6aa63c09da7d79a10111`.

Run `bash scripts/prepare-regram-core.sh` after initializing that submodule and before opening the workspace. `scripts/configure_frameworks.sh` also runs it. Repeating it is safe; a conflicting checkout produces an error without overwriting local changes.

The patch contains account-scoped Regram policy hooks, message retention and edit attributes, local overflow pins, transcription provenance, external translation provenance, audio draining for transcription, the two local Swift Package path repairs needed by this checkout, and automatic Metal shader compilation for Xcode 27. It preserves the macOS core's server-message merge and adaptive Rust download scheduling.

Feature algorithms and model changes were adapted from Regram iOS at `f61df19a1d19e9821f7adcf5c74cbb23601d1683`, under the repository's GPL license. Update the patch when changing the core submodule; the parent repository does not store its uncommitted files.
