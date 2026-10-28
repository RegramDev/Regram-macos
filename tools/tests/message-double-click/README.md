# Message double-click regression

Run `python3 tools/tests/message-double-click/run.py --architecture arm64` or use `x86_64` for Rosetta. `--source-ref HEAD` runs the previous implementation as a negative control.

The harness compiles the production action policy, dispatcher, ordinary/service row event handlers, native hit exclusions, settings rows and localization helpers with isolated message and account fixtures. It checks every action, the editing-permission override, disabled actions, text/control/avatar exclusions, missing messages, selection mode and both settings pickers. The repeat wrappers and menu handlers are compiled from production too: checks verify immediate subscription, the current topic/send-as target, draft preservation, stale menus and repeat restrictions. Action endpoints record invocations; no live account, network operation, message or reaction is used. Full permissions for native reaction endpoints remain covered by `tools/tests/reaction-permissions/run.py`.

The generated source, source hashes, compiler invocation and JSON report are retained in the output directory. Runtime checks on Rosetta do not replace Intel/macOS 12 hardware validation.
