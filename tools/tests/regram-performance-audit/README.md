# Performance audit regressions

Run `python3 tools/tests/regram-performance-audit/run.py --output /tmp/regram-performance-audit`.

The six Release/STABLE tests use the current SwiftSignalKit sources and AppKit. They do not open application windows, connect accounts, or change preferences.

- The diagnostics fixture extracts the production timer, notification handlers, and appearance/disappearance/cleanup closures. Only the controller boundary, benchmark, and state store are replaced. The interval is shortened from one second to 10 ms, and application activation is a controlled Boolean. Real timers verify initial inactivity, hiding, returning, deactivation, reactivation, repeated appearance, benchmark cancellation, and cleanup.
- The complete production image loader verifies background execution, original bytes, image parsing, missing/oversize inputs, obsolete work, and disposal before late delivery. All input images and files are synthetic.

For the diagnostics negative control, add `--diagnostics-ref 881bade2 --output /tmp/regram-performance-audit-before`. It is expected to exit with test failures: the two diagnostics cases fail with the old timer and lifecycle code. The image tests still use the current loader. Compile failures do not count as a successful negative control.

`manifest.json` identifies the exact production inputs. The fixture does not emulate full navigation, database permissions, network fetching, or rendering. The full Release build and installed application check cover integration separately.
