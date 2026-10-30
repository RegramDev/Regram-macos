# Feature isolation and loading checks

Run after the current RegramCore Release/STABLE tests:

```sh
python3 tools/tests/regram-feature-isolation/run.py --output /tmp/regram-feature-isolation
python3 tools/tests/regram-feature-isolation/run-bookmarks.py --output /tmp/regram-bookmark-loading
python3 tools/tests/regram-feature-isolation/run-theme.py --output /tmp/regram-theme-switch
```

The presentation runner extracts the production translation presentation class and cache identity function. It links real RegramCore encoding, with only message and attribute access replaced by small immutable fixtures. An instrumentation counter wraps the lazy identity initializer, asserting one encoding for a mixed batch and zero for untranslated messages. Selected-provider tone/configuration, quick/hidden/missing translations and independent speech edits are checked. The 240-message timing comparison measures this validation step with and without batch reuse; it is not full rendering, database loading or live FPS.

The same runner checks the production outgoing-language policy and extracts the language chooser's actual persistence action into an isolated UserDefaults suite. It verifies user/group/channel separation, disabling one chat, reload, other accounts and preservation of legacy records. Call-site assertions reject passing namespace-less peer IDs. Old keys cannot identify a peer namespace reliably; they remain stored but need the language to be selected once for the intended chat.

The bookmark runner extracts the current production models and complete loading, fetch and lifecycle closures. Real SwiftSignalKit queues, transactions and cancellation operators are used with in-memory bookmark, Postbox and engine boundaries. Projection helpers assert execution outside both main and database queues. Checks cover an initially hidden page, 100 obsolete queued queries plus the latest query, hiding before a database body executes, returning and reloading, fetch cancellation and suppression of late navigation. No real account, messages, clipboard, network, credentials or settings are accessed.

The theme runner extracts the application theme subscription and its application closure, and uses real SwiftSignalKit with synthetic settings and a renderer. It blocks the shared resource queue, holds an in-flight render, queues 100 obsolete settings, and holds main-thread delivery while replacing a result. Only the latest request may complete. Cloud theme identity, display scale, duplicate suppression and disposal are checked. The actual application closure must update each fixture window without requesting a full-window snapshot transition and must refresh its application context. This establishes queue, cancellation and application-call behavior; it does not measure system appearance notification latency, compositor animation or live page-switch timing.

Each negative control must compile and then return nonzero from an assertion:

```sh
python3 tools/tests/regram-feature-isolation/run.py --uncached-control --output /tmp/regram-feature-isolation-uncached
python3 tools/tests/regram-feature-isolation/run-bookmarks.py --db-projection-control --output /tmp/regram-bookmark-loading-db-control
python3 tools/tests/regram-feature-isolation/run-theme.py --shared-queue-control --output /tmp/regram-theme-switch-shared
python3 tools/tests/regram-feature-isolation/run-theme.py --snapshot-control --output /tmp/regram-theme-switch-snapshot
```

They restore per-access configuration encoding, database-queue projection, theme preparation on the shared resource queue or full-window snapshot application only in generated temporary sources. The source tree is unchanged. Manifests identify the input hashes and fixture boundaries. Core's feature-isolation matrix and the service editor's two simultaneous editors separately cover scoped service revisions and credential retry without Keychain or external requests.
