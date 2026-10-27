Run on ARM macOS using the existing Release build cache:

```sh
python3 tools/tests/regram-group-call-main-start/run.py
```

Use `--products /absolute/path/to/Release` to select another existing ARM Release `SwiftSignalKit.o` and module. The runner checks the object's architecture, performs one small optimized Swift compilation with STABLE, and never invokes SwiftPM or an app build.

Each run extracts the current cached-panel fallback Signal from `getGroupCallPanelData` in production `GroupCallLaunch.swift`, including its actual trailing operators. The fixture contains only an insertion marker; it does not add or hardcode `runOn`. Source boundaries are checked and the extracted expression's SHA256 is printed. Changes to the function's shape require reviewing the extraction rather than silently testing an old implementation.

The original 20 queue and lifetime checks are retained. A background database publisher must return while main is intentionally not draining. Cancellation before main startup prevents context creation. Replacing a pending call starts only the newest one. Panel callbacks remain on main. Disposed queued callbacks cannot emit, and proxy captures are released. Reentrant cancellation during synchronous initial delivery releases the proxy. A subscription already on main still delivers inline.

Actual Release SwiftSignalKit, QueueLocalObject, MetaDisposable, ValuePipe, and subscriber cancellation run in the fixture. Account values, cached call resources, panel values, and proxy lifetime tracking are substitutes. No real Postbox, account, network, call, audio, window, or application is accessed. Temporary source and binary files are removed after execution. This validates the fallback's queue/lifecycle behavior; it does not measure production folder-switch latency or test the other group-call branches.
