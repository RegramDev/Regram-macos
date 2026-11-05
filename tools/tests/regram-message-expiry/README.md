# Regram message expiry and opacity checks

Build Release/STABLE and run `tools/tests/regram-native-ui/run.py` first, then:

```sh
python3 tools/tests/regram-message-expiry/run.py --native-output /tmp/regram-native-ui --output /tmp/regram-message-expiry
```

The runner uses the Release module and linker arguments from the native UI checks. It extracts the actual expiry mutation, timer selection and message opacity expressions. A transaction fixture records updates using real Postbox messages, TelegramCore timeout attributes and serialization.

Checks cover timer independence, preservation of timeout metadata and protected media, persistent paused countdowns, redundant updates, and the retention/dimming switch combinations. It does not send messages, alter real account settings or simulate server RPC delivery.
