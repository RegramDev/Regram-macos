Run after building the current RegramCore Release products:

```sh
python3 tools/tests/regram-message-bookmarks/run.py --products /path/to/current/RegramCore/release
```

The runner compiles the complete production message/media settings controller and the production prefix of `RegramMessageMenu.swift` through its speech and bookmark actions. Only unrelated menu actions after bookmarks are excluded. Imports, public visibility, and shared preference/bookmark singletons are adjusted in the temporary compilation unit. Real RegramCore and SwiftSignalKit objects are linked, with a temporary copy of the Core localization bundle. The schema, preference persistence, bookmark storage, settings routing, and validation logic remain production implementations.

The fixture reuses native InputData row equivalence from the network editor harness and input/general entry shapes from the service editor harness. Windows, navigation, layout, unrelated screens, chat context, and speech are in-memory substitutes. A unique UserDefaults suite is removed on exit. No shared user preference suite, real account, window, speech service, network, or clipboard is used.

Coverage includes the default enabled switch on the message actions tab, persistence after switching off, add/edit menus hidden while off, old menu handlers unable to open editors, old editors unable to save, existing bookmarks/tags/thread metadata retained, search still reaching the switch, re-enable recovery, and independent account settings. Existing exclusions for local messages, secret chats, and secret media remain covered. This does not render the actual settings sidebar or verify pixel placement; the app's SettingsUI owner covers sidebar visibility and selection separately.
