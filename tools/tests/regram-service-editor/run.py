from pathlib import Path
import argparse
import platform
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--products", type=Path, default=ROOT / "packages/RegramCore/.build/release")
    parser.add_argument("--controller-source", type=Path, default=ROOT / "packages/RegramUI/Sources/RegramUI/RegramServiceController.swift")
    args = parser.parse_args()
    shared = (ROOT / "tools/tests/regram-network-policy/NetworkEditorChecks.swift").read_text().split("struct RegramDNSResult", 1)[0]
    shared = shared.replace("RegramNetworkEditorChecks.", "RegramServiceEditorChecks.")
    shared = shared.replace("    case string(String)\n", "    case string(String)\n    case none\n")
    shared = shared.replace("case none, next, loading, switchable(Bool), contextSelector", "case none, next, loading, context(String), switchable(Bool), contextSelector")
    shared = shared.replace('        case .loading: return "loading"\n', '        case .loading: return "loading"\n        case let .context(value): return value\n')
    shared = shared.replace("    let afterDisappear:", "    var afterDisappear:")
    shared = shared.replace("    var onDeinit:", "    var willDisappear: ((Bool) -> Void)?\n    var onDeinit:")
    shared = shared.replace('entries.first { $0.identifier == key }!', '{ guard let entry = entries.first(where: { $0.identifier == key }) else { fatalError("Missing fixture entry " + key + ": " + entries.map { $0.identifier }.joined(separator: ", ")) }; return entry }()')
    shared = shared.replace("state: MenuState) {", "state: MenuState, removeTail: Bool = true) {")
    production = args.controller_source.read_text()
    audio_boundary = 'Bundle.module.url(forResource: "RGSTTTest", withExtension: "m4a")'
    if production.count(audio_boundary) != 1:
        raise RuntimeError("Review the changed STT audio resource boundary")
    production = "\n".join(line for line in production.splitlines() if not line.startswith("import "))
    production = production.replace("RegramFormController(", "InputDataController(").replace("public func Regram", "func Regram").replace("RegramPreferences.shared", "testPreferences").replace(audio_boundary, "fixtureTestAudioURL()")
    llm = (ROOT / "packages/RegramServices/Sources/RegramServices/RGLLMTranslate.swift").read_text().split("private final class RGTranslationRequestLimiter", 1)[0]
    transcription = (ROOT / "packages/RegramServices/Sources/RegramServices/RGOpenAITranscriptionProvider.swift").read_text().split("public enum RGOpenAITranscriptionProvider", 1)[0]
    stt = (ROOT / "packages/RegramServices/Sources/RegramServices/RGSTTConfiguration.swift").read_text()
    with tempfile.TemporaryDirectory(prefix="regram-service-editor-") as temporary:
        directory = Path(temporary)
        source = directory / "ServiceEditorChecks.swift"
        source.write_text(shared + "\n" + llm + "\n" + transcription + "\n" + stt + "\n" + (HERE / "ServiceEditorChecks.swift").read_text() + "\n" + production)
        binary = directory / "service-editor-checks"
        command = ["xcrun", "swiftc", "-O", "-D", "STABLE", "-parse-as-library", "-target", platform.machine() + "-apple-macos12.0", "-I", str(args.products), str(args.products / "RegramCore.o"), str(args.products / "SwiftSignalKit.o"), str(source), "-o", str(binary)]
        subprocess.run(command, check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
