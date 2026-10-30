# Protected media capture regression

Run with a Release/STABLE native UI build command:

```sh
python3 tools/tests/regram-capture-policy/run.py --native-output /tmp/regram-ui-refine-20261029/verified --output /tmp/regram-capture-checks
```

The fixture extracts the actual chat image, gallery thumbnail and gallery window capture conditions. It compiles the production export policy and gallery extension against real Telegram `Message`, `GalleryEntry` and AppKit image layers. It checks setting changes, account separation, cached peer restrictions, secret/expired/paid media, and whether a permitted image reaches the normal image layer. Only isolated fixture preferences and synthetic media are used. This does not replace a system screenshot check in the installed app.
