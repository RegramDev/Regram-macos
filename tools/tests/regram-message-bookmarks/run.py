from pathlib import Path
import argparse
import platform
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise RuntimeError("Review the changed fixture boundary: " + old)
    return source.replace(old, new)


def production_source(path):
    return "\n".join(line for line in path.read_text().splitlines() if not line.startswith("import ")).replace("public func Regram", "func Regram").replace("RegramPreferences.shared", "testPreferences").replace("RGMessageBookmarks.shared", "testBookmarks")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--products", type=Path, default=ROOT / "packages/RegramCore/.build/release")
    args = parser.parse_args()
    shared = (ROOT / "tools/tests/regram-network-policy/NetworkEditorChecks.swift").read_text().split("struct EditorPeerId", 1)[0]
    shared = replace_once(shared, "    case string(String)\n", "    case string(String)\n    case none\n")
    shared = replace_once(shared, "enum InputDataValidation { case fail(Failure); enum Failure { case none } }", "enum InputDataValidation { case fail(Failure), success(Success); enum Failure { case none }; enum Success { case navigationBack } }")
    shared = replace_once(shared, "handler: @escaping () -> Void, state: MenuState)", "handler: @escaping () -> Void, itemImage: NSImage? = nil, state: MenuState = .off)")
    shared = replace_once(shared, "    let updateDatas:", "    let validateData: ([InputDataIdentifier: InputDataValue]) -> InputDataValidation\n    let tableView = FixtureTableView()\n    let updateDatas:")
    shared = replace_once(shared, "updateDatas: @escaping ([InputDataIdentifier: InputDataValue]) -> InputDataValidation,", "updateDatas: @escaping ([InputDataIdentifier: InputDataValue]) -> InputDataValidation = { _ in .fail(.none) }, validateData: @escaping ([InputDataIdentifier: InputDataValue]) -> InputDataValidation = { _ in .fail(.none) },")
    shared = replace_once(shared, "removeAfterDisappear: Bool, hasDone: Bool, identifier: String)", 'removeAfterDisappear: Bool = false, hasDone: Bool = false, identifier: String = "fixture", afterTransaction: ((InputDataController) -> Void)? = nil)')
    shared = replace_once(shared, "        self.updateDatas = updateDatas;", "        self.validateData = validateData; self.updateDatas = updateDatas;")
    rows = (ROOT / "tools/tests/regram-service-editor/ServiceEditorChecks.swift").read_text().split("var serviceNotices", 1)[0]
    rows = replace_once(rows, "struct InputDataEntryId { let value: String }", "struct InputDataEntryId { let value: String; var identifier: InputDataIdentifier? { InputDataIdentifier(value) } }")
    rows = replace_once(rows, "final class PrecieSliderRowItem {", "final class PrecieSliderRowItem {\n    init(_ size: NSSize, stableId: InputDataEntryId, current: CGFloat, markers: [String], showValue: String, update: @escaping (CGFloat) -> Void, viewType: GeneralViewType) {}")
    menu = production_source(ROOT / "packages/ChatUI/Sources/ChatUI/RegramMessageMenu.swift")
    boundary = "    if message.rgEditHistory != nil {"
    if menu.count(boundary) != 1:
        raise RuntimeError("Review the changed menu boundary following bookmark actions")
    menu = menu.split(boundary, 1)[0] + "    _ = protected\n    return result\n}\n"
    ui = production_source(ROOT / "packages/RegramUI/Sources/RegramUI/RegramMessageMediaSettingsController.swift")
    with tempfile.TemporaryDirectory(prefix="regram-message-bookmark-checks-") as temporary:
        directory = Path(temporary)
        source = directory / "BookmarkChecks.swift"
        source.write_text(shared + "\n" + rows + "\n" + (HERE / "BookmarkChecks.swift").read_text() + "\n" + ui + "\n" + menu)
        shutil.copytree(args.products / "RegramCore_RegramCore.bundle", directory / "RegramCore_RegramCore.bundle")
        binary = directory / "bookmark-checks"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", platform.machine() + "-apple-macos12.0", "-I", str(args.products), str(args.products / "RegramCore.o"), str(args.products / "SwiftSignalKit.o"), str(source), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
