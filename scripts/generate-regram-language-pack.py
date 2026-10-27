#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "localization/Regram"
LANGUAGES = {"en": "en", "zh-Hans": "zh-hans", "zh-Hant": "zh-hant"}


def strings_text(values, insert_before=None):
    insert_before = {} if insert_before is None else insert_before
    if not isinstance(insert_before, dict):
        raise ValueError("String ordering constraints must be an object")
    predecessors = {}
    for key, anchor in insert_before.items():
        if not isinstance(key, str) or not isinstance(anchor, str) or key not in values or anchor not in values or key == anchor:
            raise ValueError(f"Invalid string ordering constraint: {key} before {anchor}")
        predecessors.setdefault(anchor, []).append(key)
    ordered = []

    def append(key):
        for predecessor in sorted(predecessors.get(key, [])):
            append(predecessor)
        ordered.append(key)

    for key in sorted(values):
        if key not in insert_before:
            append(key)
    if len(ordered) != len(values):
        raise ValueError("String ordering constraints contain a cycle")
    return "".join(json.dumps(key, ensure_ascii=False) + " = " + json.dumps(values[key], ensure_ascii=False) + ";\n" for key in ordered)


def placeholders(value):
    value = value.replace("%%", "")
    return sorted(re.findall(r"%(?:\d+\$)?[-+#0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|[hlLzjt])?[@diuoxXfFeEgGcs]", value)) + sorted(re.findall(r"\{[A-Za-z][A-Za-z0-9_]*\}", value))


def generate(check=False, ios_root=None):
    manifest = json.loads((SOURCE / "manifest.json").read_text())
    aliases = manifest["macosAliases"]
    macos_insert_before = manifest.get("macosInsertBefore", {})
    packs = {language: json.loads((SOURCE / (language + ".json")).read_text()) for language in LANGUAGES}
    reference = packs["en"]
    outputs = {}
    for language, ios_language in LANGUAGES.items():
        pack = packs[language]
        for group in ["strings", "macos", "nativeMacos"]:
            if pack[group].keys() != reference[group].keys():
                raise ValueError(f"{language}: inconsistent keys in {group}")
            for key, value in pack[group].items():
                if not isinstance(value, str) or not value.strip():
                    raise ValueError(f"{language}: empty value for {key}")
                if placeholders(value) != placeholders(reference[group][key]):
                    raise ValueError(f"{language}: format arguments differ for {key}")
        macos = pack["strings"] | pack["macos"]
        macos.update({alias: macos[key] for alias, key in aliases.items()})
        macos.update({"native.macos." + key: value for key, value in pack["nativeMacos"].items()})
        outputs[ROOT / f"packages/RegramCore/Sources/RegramCore/Resources/{language}.lproj/Regram.strings"] = strings_text(macos, macos_insert_before)
        ios = pack["strings"]
        outputs[ROOT / f"localization/generated/ios/{ios_language}.lproj/RGLocalizable.strings"] = strings_text(ios)
        if ios_root is not None:
            outputs[ios_root / f"Regram/RGStrings/Strings/{ios_language}.lproj/RGLocalizable.strings"] = strings_text(ios)
    for path, content in outputs.items():
        if check:
            if not path.is_file() or path.read_text() != content:
                raise ValueError(f"Regenerate language resources: {path}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        subprocess.run(["plutil", "-lint", str(path)], check=True, stdout=subprocess.DEVNULL)
    print(f"Regram language pack: {len(reference['strings'])} shared keys, {len(reference['macos'])} platform overrides, {len(reference['nativeMacos'])} native macOS strings; all three languages validated")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--ios-root", type=Path)
    args = parser.parse_args()
    generate(check=args.check, ios_root=args.ios_root)
