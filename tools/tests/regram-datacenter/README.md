Run from the repository root:

```sh
python3 tools/tests/regram-datacenter/run.py
```

The runner compiles the complete production `RegramDatacenterController.swift`, the real TelegramCore probe sample structure, the cached Release RegramCore statistics implementation, and SwiftSignalKit. It reuses the existing network editor fixture for InputData rows. Rows with unchanged display fields retain their original action, matching native action-independent row equality. It does not rebuild packages or the app.

Five separately controlled probe signals replace account networking. Proxy settings and connection status use in-memory signals. Only the production clipboard boundary is replaced with an in-memory pasteboard; no real clipboard, accounts, preferences, app process, or remote connections are used. Imports and the controller's public visibility are adjusted only in the generated temporary compilation unit.

Coverage includes DC5 finishing first, DC1 failing or remaining unfinished, DC2/3/4 finishing later, and the original reused copy row reading all latest averages from the controller's Atomic state. Successful results remain available while other DCs fail or wait. Retry resets results and creates five new subscriptions. Cancellation, all proxy route types, page disappearance, app inactivity, and controller destruction dispose pending requests. Late samples and completion events, including a background result queued before cancellation, cannot alter the current run or copied report.

Cancellation tests exercise actual SwiftSignalKit disposal and production generation guards together. They do not bypass disposed subscribers to directly invoke private closures. The network worker, socket timing, DC selection, real proxy changes, and rendered UI pixels remain outside this controller test.
