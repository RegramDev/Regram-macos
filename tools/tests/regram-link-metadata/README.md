Run `python3 tools/tests/regram-link-metadata/run.py` after building RegramCore Release for the current architecture. Use `--products` for another directory containing RegramCore.o, SwiftSignalKit.o and their Swift modules.

The fixture compiles the production RegramLinkMetadata file. It removes only the TelegramEngine refresh method and its TelegramCore import, then redirects the constructor's cache read to an isolated UserDefaults suite. It keeps the real previewUrl implementation, bundled default domain rules, Foundation URL/regex behavior and RegramCore link rules.

Coverage includes the Miyoushe /ys/#/article route with and without a tracking query, X query/fragment removal, generated m.moec/sir Instant View query retention, unchanged unmatched/domain-without-rule URLs, disabled repair and malformed URLs. No Telegram engine, refresh request, real user cache or app process is used. The isolated suite and compiled temporary artifacts are removed afterward.
