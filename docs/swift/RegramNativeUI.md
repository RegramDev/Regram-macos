# Regram native feature and settings UI

All new Regram feature and settings interfaces should follow macOS interaction conventions and use the shared Regram native form components. Keep these components in RegramUI; do not move feature-specific logic into UI hubs.

## Forms

Use `RegramFormController` with ordinary `InputDataEntry` values. Prefer `RegramPageBuilder` to derive first/inner/last row grouping automatically. The adapter preserves identifiers and form callbacks while creating AppKit controls. Existing feature navigation, lifecycle cancellation, validation and copy permissions still belong to the page.

| User intent | Component |
| --- | --- |
| Enable or disable an independent setting | NSSwitch through `.switchable` |
| Choose several independent items | Native checkbox through `.selectable` |
| Choose one item from a searchable list | `.selectable` with controller `selectionStyle: .single` |
| Select a value from a menu | NSPopUpButton through `.contextSelector` |
| Switch a short set of categories | `regramSegmentedRowItem`, reusing Telegram `GlassSegmentView` |
| Adjust a numerical value | `regramSliderRowItem`, with a meaningful value formatter |
| Edit text, URLs or prompts | `.input`; use `.secure` for credentials |
| Perform an action | `.none` with an explicit action, rendered as a native button |
| Open a child page | `.next` with an explicit navigation action |
| Display an empty/loading result | `RegramEmptyRowItem` |
| Search settings | `RegramPageBuilder.search`, reusing Telegram's `SearchRowView` and `SearchView` |

Native rows create accessories on demand. Build popup choices when the menu opens, and reject menu actions from a previous row binding. Keep expensive work out of row binding and scrolling.

Use complete menu titles for long model identifiers or folder names (`ContextMenuItem(removeTail: false)`). Use stable option IDs and derive selection from the saved model. Do not execute option handlers while binding views.

## Organization and behavior

Use concise section headings and explain the effect of unfamiliar settings. Place mutually exclusive choices in a single selector. Show service-specific configuration when relevant, preserve hidden values, and keep settings-search destinations reachable. Keep destructive actions in a separate group and retain their confirmation flow. Provide cancellation for ongoing operations and stop page-owned work when the page becomes hidden.

Use system typography and the existing centered content column. Measure native text with `regramNativeTextHeight`, which includes AppKit label insets; a bounding rectangle without these insets can hide the last line. Support narrow panes and both appearances. Short fields use aligned label and editor columns when space permits; stack them in narrow panes and for multiline text. Use regular 13-point labels, smaller secondary descriptions and compact section spacing. Use semantic SF Symbols for feature categories. Use existing AppKit/AVFoundation/WebKit content views for media rather than introducing a second form design around them.

Use `tools/tests/regram-native-ui/run.py` after a Release/STABLE build to check native geometry, actions, editing, IME, accessibility exposure and navigation. Its synthetic hidden windows do not substitute for checking the installed application. Install user-testing builds through `scripts/install-regram-release.py` with the existing fixed signing identity and retain local data.

## Current visual baseline

Use the user-approved 283386 AppKit form structure as the baseline. Preserve grouped first/inner/last rows and existing controls. Use 14-point group corners, quieter inset separators and 16-point section spacing. Do not turn every row into a separate capsule or replace the form with Telegram row implementations without a new request.

The user explicitly requested Telegram's search control after the AppKit search field rendered an opaque rectangular editor and focus ring. Reuse `SearchRowItem`/`SearchRowView` and `SearchView` for Regram settings search, including its focus animation, clear button and IME behavior. Keep the outer row transparent through theme changes and resizing. Use `regramRestoreSearchQuery`; the settings home passes `autofocusSearch: false` so entering or returning to the page does not steal search focus. Keep the search column aligned with the grouped rows and avoid an extra glass wrapper.

Category selectors reuse Telegram `GlassSegmentView` at its intrinsic width in a centered horizontal viewport. Keep its single glass surface shadowless; do not add a second backdrop or an AppKit segmented bezel. Preserve full labels, reveal the selected category in narrow panes, support keyboard navigation and radio accessibility, and reject stale actions after a row is rebound. Ordinary scrolling rows must remain lightweight. The shared glass implementation supplies reduced-transparency and lite-mode fallback.

The macOS settings UI must not expose the removed full-data wipe feature or its search/deep-link actions. Preference backup/reset is a separate existing feature.
