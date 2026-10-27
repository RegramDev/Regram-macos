from pathlib import Path
import subprocess
import tempfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def block(source, start):
    position = source.index(start)
    opening = source.index("{", position)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[position:end]


source = (ROOT / "packages/SettingsUI/Sources/SettingsUI/AccountViewController.swift").read_text()
hooks = (ROOT / "packages/SettingsUI/Sources/SettingsUI/SettingsHooks.swift").read_text()
helper = block(source, "private func accountRegramSettingsRowId(")
navigation = block(source, "open override func navigationWillChangeController()")
navigation = navigation.replace("open override func", "override func", 1)
protocol = block(hooks, "public protocol SettingsChatController:")
binding_start = source.index("disposable.set(apply.start(next:")
binding = source[binding_start:binding_start + 250]
assert "self?.tableView.merge(with: transition)" in binding
assert "self?.navigationWillChangeController()" in binding
saved = source.index("let messageBookmarksEnabled = RegramPreferences.shared.settings")
group = source[saved:source.index("entries.append(.whiteSpace", saved)]
assert '.savedMessages(index: index, viewType: .singleItem)' in group
assert 'if messageBookmarksEnabled {' in group
assert '.bookmarks(index: index, viewType: .singleItem)' in group
assert 'guard RegramPreferences.shared.settings(accountId: arguments.context.peerId.toInt64())["messageBookmarksEnabled"].bool else { return }' in source
adapters = (HERE / "Adapters.swift").read_text()
tests = (HERE / "Checks.swift").read_text()
with tempfile.TemporaryDirectory(prefix="regram-settings-selection-") as folder:
    directory = Path(folder)
    program = directory / "main.swift"
    executable = directory / "checks"
    program.write_text(adapters + "\n" + protocol + "\n" + helper + "\nfinal class SelectionHarness: ViewController {\n typealias Context = FixtureContext\n let context = Context(peerId: 42)\n let tableView = FixtureTable()\n" + navigation + "\n}\n" + tests)
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-DSTABLE", "-warnings-as-errors", str(program), "-o", str(executable)], cwd=ROOT, check=True)
    subprocess.run([str(executable)], cwd=ROOT, check=True)
print("Current table-merge binding, bookmark group visibility and stale-row guard checks passed.")
