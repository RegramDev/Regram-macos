from pathlib import Path
import argparse
import hashlib
import json
import shlex
import subprocess


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--architecture", choices=["arm64", "x86_64"], default="arm64")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--source-ref")
    options = parser.parse_args()
    output = options.output or Path("/tmp/regram-message-double-click-" + options.architecture)
    output.mkdir(parents=True, exist_ok=True)
    paths = {
        "POLICY": "packages/RegramCore/Sources/RegramCore/RegramInputMediaPolicy.swift",
        "HANDLER": "packages/ChatUI/Sources/ChatUI/RegramMessageDoubleClick.swift",
        "ROW": "packages/ChatUI/Sources/ChatUI/ChatRowView.swift",
        "SERVICE": "packages/ChatUI/Sources/ChatUI/ChatServiceItem.swift",
        "SETTINGS": "packages/RegramUI/Sources/RegramUI/RegramMessageMediaSettingsController.swift",
        "REPEAT": "packages/ChatUI/Sources/ChatUI/RegramRepeatMessages.swift",
        "MENU": "packages/ChatUI/Sources/ChatUI/RegramMessageMenu.swift",
        "DEFERRED": "packages/ChatUI/Sources/ChatUI/ChatDeferredSendAction.swift",
    }
    sources = {key: subprocess.check_output(["git", "show", options.source_ref + ":" + path], cwd=ROOT, text=True) if options.source_ref else (ROOT / path).read_text() for key, path in paths.items()}
    markers = {
        "POLICY": ("POLICY", "public enum RGMessageDoubleClickAction:"),
        "HANDLER": ("HANDLER", "func regramHandleMessageDoubleClick("),
        "ELIGIBILITY": ("ROW", "public func isAllowedToDoubleAction("),
        "ROW_ACTION": ("ROW", "public override func doubleClick("),
        "SERVICE_ACTION": ("SERVICE", "public override func doubleClick("),
        "ROWS": ("SETTINGS", "private func regramParityRows("),
        "ROW_TYPE": ("SETTINGS", "private enum RegramParityRow"),
        "TITLE": ("SETTINGS", "private func regramParityText("),
        "VALUE_TITLE": ("SETTINGS", "private func regramParityValueTitle("),
        "REPEAT_FORWARD": ("REPEAT", "func regramRepeatForward("),
        "REPEAT_COPY": ("REPEAT", "func regramRepeatCopy("),
        "CAN_REPEAT": ("REPEAT", "func regramCanRepeatHere("),
        "DEFERRED": ("DEFERRED", "public final class ChatDeferredSendAction"),
        "MENU_FORWARD": ("MENU", 'result.append(ContextMenuItem(menuTitle("menu.repeatForward"), handler: {'),
        "MENU_COPY": ("MENU", 'result.append(ContextMenuItem(menuTitle("menu.repeatCopy"), handler: {'),
    }
    fixture = (HERE / "Checks.swift").read_text()
    for key, (source, marker) in markers.items():
        code = declaration(sources[source], marker)
        if key in ["ROW_ACTION", "SERVICE_ACTION", "MENU_FORWARD", "MENU_COPY"]:
            code = code[code.index("{") + 1:-1]
        fixture = fixture.replace("__" + key + "__", code)
    generated = output / "main.swift"
    generated.write_text(fixture)
    binary = output / "checks"
    command = ["xcrun", "swiftc", "-O", "-D", "STABLE", "-target", options.architecture + "-apple-macos12.0", str(generated), "-o", str(binary)]
    (output / "compile-command.txt").write_text(shlex.join(command) + "\n")
    with (output / "compile.log").open("w") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print((output / "compile.log").read_text())
        raise SystemExit(result.returncode)
    result = subprocess.run(["arch", "-" + options.architecture, str(binary), str(output / "report.json")])
    report = json.loads((output / "report.json").read_text())
    report.update({"architecture": options.architecture, "minimumMacOS": "12.0", "sourceRef": options.source_ref, "productionSources": {paths[key]: hashlib.sha256(value.encode()).hexdigest() for key, value in sources.items()}, "liveAccountUsed": False, "networkActionsExecuted": False})
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
