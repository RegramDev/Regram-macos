# Saved music loading and mutations

Run from the repository root:

```sh
python3 tools/tests/saved-music-loading/run.py --output /tmp/regram-saved-music-loading
```

The runner uses Release/STABLE and real SwiftSignalKit. It extracts the complete production `ProfileSavedMusicContext`, add/remove helpers and their shared list helpers, plus the audio picker's loading, empty-state and section expressions. The generated package, source hashes, actual command, test log and parsed report remain in the output directory. XCTest console results are used when SwiftPM's XML contains only its empty Swift Testing suite; a run with no executed cases fails.

The 51 cases cover retry after errors, empty completion and missing peers; cached rows during reload; late cache reads; raw server offsets despite duplicate or unsupported documents; metadata refresh; empty-page exhaustion; reentrant observers; lazy mutation subscription; cancellation and overlapping mutation completion; request-start order; server rejection; cache, saved-ID and header consistency; foreign-profile isolation; self/missing anchors; repeated removal; and context lifetime.

Two added cases retain a cache transaction callback even after its subscription is cancelled, then invoke it after a confirmed mutation or a newer reload. Its body must reject the stale generation. The other two retain an unsubscribed mutation signal after context deallocation and check a server-rejected optimistic mutation through refresh.

For a negative control, supply a saved pre-fix production file:

```sh
git -C submodules/telegram-ios show HEAD:submodules/TelegramCore/Sources/TelegramEngine/Peers/SavedMusic.swift > /tmp/SavedMusic.before.swift
python3 tools/tests/saved-music-loading/run.py \
  --core-source /tmp/SavedMusic.before.swift \
  --output /tmp/regram-saved-music-before
```

`--ui-source` selects another picker source; `--filter` selects focused XCTest cases. The original 47 cases retain their assertions. The core fix is persisted in `patches/regram-telegram-core.patch` against the pinned `telegram-ios` revision.

Account, Postbox transactions, API responses, media metadata, file-reference revalidation and picker rows are controlled adapters. The tests execute production logic and real signal disposal, but do not use real accounts, server mutations, audio hardware or native playback. The retained stale-transaction callbacks model cancellation after a database operation has already become runnable; they are not a concurrent live Postbox test.
