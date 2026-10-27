# Focus-triggered appearance refresh

```sh
python3 tools/tests/regram-focus-appearance/run.py --output /tmp/regram-focus-appearance-after
```

The fixture compiles the production `RegramFontAppearanceBinding`, its binding function, the actual `InterfaceFontProvider`, and the production `appearanceSignal` expression. It uses cached SwiftSignalKit, native NSFont and two hidden NSWindow instances. Synthetic key notifications go through the real NotificationCenter; no window is ordered front or activated. Preferences, font storage and font resolution are in-memory boundaries; no real account data, preferences or font files are accessed.

The assertions cover repeated activation of the same binding, a real configuration change missed by notifications, normal preference updates, actual font-store notifications, requested size/weight/italic forwarding, native fallback when interface fonts are disabled, account/window changes, two windows for the same account, inactive-binding disposal and stale notifications after disposal. A separate palette change still flows through the production appearance signal.

`report.json` records font invalidations, appearance emissions and theme-copy counts. The key regression is 20 notifications for an unchanged binding: the old implementation performs 40 font invalidations and theme copies, while the fixed implementation performs zero. Meaningful account/window changes retain the existing install/force behavior.

For a negative control, pass a saved pre-fix bridge:

```sh
python3 tools/tests/regram-focus-appearance/run.py --source /tmp/regram-focus-appearance-before.swift --output /tmp/regram-focus-appearance-before
```

That command must return nonzero. The runner records production extraction hashes in `manifest.json`. Only the font binding class/function is extracted from the bridge; localization code is excluded and remains unchanged.

This verifies elimination of extra appearance refreshes. It does not measure live application switching, render AppKit's active/inactive compositor colors, or change native glass materials. The four user-reported chrome areas still require inspection in the next installed Release build.
