# Folder selection and header regressions

Run against the existing ARM Release cache, without SwiftPM planning or rebuilding the application:

```sh
python3 tools/tests/regram-folder-switch/run.py --output /tmp/regram-folder-switch-after
```

The runner extracts the current production top-folder callback, base/subclass selection methods, `updateFilter`, `FilterData`, Sidebar bridge, archive signal expression, header content/layout blocks, and native segment cache binding. It compiles one small executable with cached Release package objects and actual SwiftSignalKit and TGUIKit. `manifest.json` records source hashes and extraction markers; `report.json` contains assertions and observations.

The route checks observe state emission order and count, premium rejection, folder polling/disposal, selection persistence, search/reveal reset, same-folder scrolling, and Sidebar parity. The archive checks count subscriptions and emissions across activity/state noise, unrelated settings, folder changes, relevant setting toggles, real source updates and separate account IDs.

The scroll checks extract the production pagination callback and initial request policy. They exercise unchanged state, duplicate page cursors and legitimate next pages. Native NSScrollView geometry covers empty, short, 80-chat and 500-chat fixture lists: the first short scroll retains the initial scrollbar proportion. Window heights 350/700/1400/2800 use the same initial capacity as native pagination. These checks do not measure live-account frame rates.

Use `--negative-scroll /tmp/regram-scroll-before-20261029` with an earlier ChatListController.swift to restore the former request and callback policy; it must fail the startup geometry and duplicate-work assertions. The 2026-10-29 candidate passes 112 checks, while this negative control fails 17.

The geometry checks execute production header/layout blocks around actual `ScrollableSegmentView` instances. They cover 20 folders, light/dark colors, repeated widths 320/600/1000, equal-content reapplication, selected-item visibility, native custom-label factory counts, hidden/show transitions, empty-then-populated headers and footer placement. Model identities are retained across equal content so native segment views remain available for resize autoscroll.

Account, engine, navigation, preference storage and row content are in-memory fixtures. The fixture does not execute the complete account-dependent `ChatListRevealView.set` badge/inline-sticker pipeline or launch Regram business code. Full ChatListUI semantic checking complements these boundary tests. The executable has a separate bundle identifier, activation is prohibited, no windows are displayed, and only installed `Assets.car` is copied for TGUIKit's default image literals. No account data or credentials are read. This is a regression suite, not a latency benchmark or live UI acceptance.

Two optional negative controls accept source snapshots taken before the fix:

```sh
python3 tools/tests/regram-folder-switch/run.py --negative-control /tmp/regram-folder-switch-before --output /tmp/regram-folder-switch-negative-control
python3 tools/tests/regram-folder-switch/run.py --negative-layout /tmp/regram-folder-switch-before/ChatListRevealItem.swift --output /tmp/regram-folder-switch-negative-layout
```

The first replaces only the route, archive expression and geometry block with their old production implementations; current selection methods remain available to the harness. It must fail the request/side-effect, archive restart and duplicate-header assertions. The second replaces only the old production native header layout and must fail selected-tab visibility after narrowing. Both commands are expected to return nonzero. The default command must return zero.
