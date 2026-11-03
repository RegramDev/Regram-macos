# Sponsored-message filtering regressions

```sh
python3 tools/tests/regram-sponsored-messages/run.py
python3 tools/tests/regram-sponsored-messages/run.py --revision 8a75721b --output /tmp/regram-sponsored-messages-20261103/presentation-before
swift test -c release -Xswiftc -DSTABLE --package-path packages/RegramCore --filter RegramSponsoredContentTests
```

The presentation runner compiles the current production conditions and projections for bot headers, proxy headers, search peer filtering, channel ads, proxy list items, delayed video ads and video overlay removal. It uses isolated presentation models and preferences, plus the real SwiftSignalKit disposal types. It does not contact an advertising service or modify user preferences. The full Release/STABLE application build validates the actual Telegram and AppKit types and module integration.

The presentation suite has eight cases. Against `8a75721b`, five cases fail with eight assertions, reproducing the missing bot, proxy-header, search and video filtering. All eight cases pass after the fix. Existing channel filtering, proxy list filtering and ordinary search deduplication remain covered.

The six `RegramSponsoredContentTests` exercise the actual shared signal implementation: hidden startup, cancellation, late callbacks, cached fixed and dynamic ads, repeated settings, completed requests and independent visibility streams.
