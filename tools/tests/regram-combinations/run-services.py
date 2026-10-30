from pathlib import Path
import argparse
import hashlib
import json
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def declaration(source, marker):
    start = source.index(marker)
    cursor = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


parser = argparse.ArgumentParser()
parser.add_argument("--products", type=Path, default=ROOT / "packages/RegramCore/.build/release")
parser.add_argument("--output", type=Path, default=Path("/tmp/regram-service-combinations"))
parser.add_argument("--shared-credential-control", action="store_true")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
paths = [ROOT / "packages/RegramServices/Sources/RegramServices" / name for name in ["RGLLMTranslate.swift", "RGOpenAITranscriptionProvider.swift", "RGSTTConfiguration.swift", "RGGTranslate.swift"]]
llm, speech, configuration, translation = [path.read_text() for path in paths]
llm_boundary = "private let rgLLMSession: URLSession = URLSession(configuration: .ephemeral)"
speech_boundary = "let sessionConfiguration = URLSessionConfiguration.ephemeral"
directory_boundary = "FileManager.default.temporaryDirectory"
if llm.count(llm_boundary) != 1 or speech.count(speech_boundary) != 1 or speech.count(directory_boundary) != 1:
    raise RuntimeError("Review the URLSession and synthetic upload-directory boundaries")
llm = llm.replace(llm_boundary, "private let rgLLMSession: URLSession = URLSession(configuration: fixtureSessionConfiguration())")
speech = speech.replace(speech_boundary, "let sessionConfiguration = fixtureSessionConfiguration()").replace(directory_boundary, "fixtureRoot")
if args.shared_credential_control:
    boundary = 'request.setValue("Bearer \\(configuration.apiKey)", forHTTPHeaderField: "Authorization")'
    if llm.count(boundary) != 1:
        raise RuntimeError("Review the credential negative control boundary")
    llm = llm.replace(boundary, 'request.setValue("Bearer translation-key-0", forHTTPHeaderField: "Authorization")')
support = [declaration(translation, marker) for marker in ["public enum TranslateFetchError", "private func rgTranslateSplitIntoChunks(", "func rgTranslateInChunks(", "public func getGTranslateLang(", "public func gtranslateSplitTextBySentences(", "func rgTranslateSequentially("]]
generated = args.output / "ServiceCombinationChecks.swift"
generated.write_text((HERE / "ServiceCombinationChecks.swift").read_text() + "\nlet rgTranslateMaxChunkLength = 1200\n" + "\n\n".join(support + [llm, speech, configuration]))
binary = args.output / "service-combination-checks"
command = ["xcrun", "swiftc", "-O", "-D", "STABLE", "-parse-as-library", "-target", platform.machine() + "-apple-macos12.0", "-I", str(args.products), str(args.products / "SwiftSignalKit.o"), str(generated), "-o", str(binary)]
(args.output / "manifest.json").write_text(json.dumps({"productionSources": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}, "sharedCredentialControl": args.shared_credential_control, "boundaries": "Full LLM and STT transport/configuration code and actual chunk/language helpers with actual SwiftSignalKit. URLSessionConfiguration has an all-request in-memory URLProtocol; upload directory is fixture-owned. No real HTTP, account, credential store, audio device or chat send path."}, indent=2) + "\n")
with (args.output / "compile.log").open("w") as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    raise SystemExit("Compile failed: " + str(args.output / "compile.log"))
result = subprocess.run([str(binary), str(args.output)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30)
(args.output / "checks.log").write_text(result.stdout)
print(result.stdout[-5000:])
raise SystemExit(result.returncode)
