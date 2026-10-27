# Search menu bookmarks and retained folder models

```sh
python3 tools/tests/regram-search-menu/run.py --output /tmp/regram-search-menu-after
```

This small fixture compiles the current production default search-header menu body, header selection callback, segment-model cache binding, and native `ScrollableSegmentItem` equality function. Navigation, menu containers, account settings and segment views are in-memory boundaries. It neither launches AppKit/Regram nor reads real accounts/preferences, and requires no package build or cached application objects.

Checks cover the exact base menu order, omission of both bookmark entry and separator when disabled, current-account isolation, a retained menu action after disabling/re-enabling, and unchanged creation actions. They also retain an equal model while replacing filter data with unchanged visible title/count, then verify the production callback resolves the latest header item. Reordering must invalidate the previous model index.

To verify the old unguarded menu is detected, pass a saved pre-fix `PeersListController.swift`:

```sh
python3 tools/tests/regram-search-menu/run.py --source /tmp/regram-search-menu-before.swift --output /tmp/regram-search-menu-negative
```

That negative control must return nonzero. Source extraction hashes and the assertion result are saved beside the generated Swift fixture. The earlier real-native geometry suite remains in `tools/tests/regram-folder-switch`; this focused check does not repeat it.
