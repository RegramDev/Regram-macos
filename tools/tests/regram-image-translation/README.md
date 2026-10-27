Run on ARM macOS using the existing Release products:

```sh
python3 tools/tests/regram-image-translation/run.py
```

Use `--products /absolute/path/to/Release` to select another existing cache containing SwiftSignalKit, RegramCore, TGUIKit and its small dependencies. The runner performs only focused Swift compilations. It never runs SwiftPM, builds the application, launches Regram, reads user images, opens a visible window, or sends translation requests.

The logic fixture dynamically extracts the current GalleryRecognition translation methods and settings observer. It compiles the new image translation service, actual selected-provider dispatch, sequential request helper, chat language policy, and LLM configuration/context policy. Real RegramCore preferences and Release SwiftSignalKit run against a unique temporary UserDefaults suite. Provider transports, credentials, source authorization, navigation and notifications to the user are memory substitutes. Telegram response entity stand-ins include missing, extra, reordered, overlapping and invalid ranges; region mapping consumes only each returned text.

Checks cover all eight providers, normalized targets, duplicate regions, numeric/empty OCR, synchronous success/nil/failure/empty completion, blank results, cancellation before startup, serial requests, no partial overlay, replacement/hidden sources, fresh source denial before requests and result application, configuration revision changes, final authorization without a value, and observer/item disposal. A 28-line synthetic screenshot requires 21 logical translations because duplicate headings share a result. Each rejected budget case makes zero provider calls and produces a readable failure notification. Maximum concurrent logical requests is asserted to be one.

The native fixture compiles the current production TranslateView, recognition value types and geometry helpers, then links real Release TGUIKit/AppKit. It creates its own prohibited-activation process, a generated CGImage, and an NSWindow which is never displayed. It checks shrinking progress and text arrays, retry after zero rows, mismatched legacy original/result counts, geometry from each translated Value.detected, and resizing.

The OCR delivery fixture dynamically extracts the actual initialization pipeline. It reproduces a background old-image result queued behind a new source event, verifies that the old value is discarded, then applies the current image and hides it. A separate negative control removes only the inner main-queue delivery in the generated temporary source and confirms the previous stale-image behavior. No production file is changed by the runner.

The image translation budget allows at most 128 regions, 12,000 total UTF16 code units, 1,000 units per region, and 24 unique regions containing letters. Empty/numeric regions retain their source text; duplicate text shares one result. Requests are serial and the entire plan is validated before starting any provider. Limits fail the whole operation rather than truncating it. The per-region limit fits every existing provider's single-chunk limit, including Microsoft's 1,000 characters. The 24-call limit counts logical translation calls, not the selected provider's existing authentication or transport retries. LLM requests stay at one chunk per unique region. A failed operation does not silently switch providers.

These checks do not exercise real Vision OCR, remote provider transports, system translation downloads/panels, real Keychain access, or a running Gallery/account. Full application integration remains the Release build and independent review's responsibility.
