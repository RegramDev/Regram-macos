from pathlib import Path
import argparse
from datetime import datetime
import json
import platform
import plistlib
import re
import subprocess
import sys


APP = Path("/Applications/Regram.app")


def process_rows():
    candidates = subprocess.run(["pgrep", "-x", "Regram"], capture_output=True, text=True, timeout=3)
    if candidates.returncode == 1:
        return []
    candidates.check_returncode()
    pids = ",".join(candidates.stdout.split())
    if not pids:
        return []
    result = subprocess.check_output(["ps", "-p", pids, "-o", "pid=,etime=,%cpu=,rss=,comm="], text=True, timeout=3)
    return [line.strip() for line in result.splitlines() if line.strip().endswith(str(APP / "Contents/MacOS/Regram"))]


def main():
    parser = argparse.ArgumentParser(description="Capture Regram process metrics and stacks while it is slow; keep the app running.")
    parser.add_argument("--duration", type=int, choices=range(3, 31), default=5, metavar="3..30")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    rows = process_rows()
    if len(rows) != 1:
        raise SystemExit("Expected one running /Applications/Regram.app process; found " + str(len(rows)))
    pid = rows[0].split()[0]
    with (APP / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    timestamp = datetime.now().astimezone().isoformat(timespec="seconds")
    output = arguments.output or Path.home() / "Library/Logs/RegramPerformance" / (datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + info["CFBundleVersion"])
    output.mkdir(parents=True, exist_ok=True)
    report = {
        "capturedAt": timestamp,
        "pid": int(pid),
        "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "architecture": platform.machine(),
        "macOS": platform.mac_ver()[0],
        "processBefore": rows[0],
        "durationSeconds": arguments.duration,
        "applicationRestartedByCapture": False,
    }
    result = subprocess.run(["sample", pid, str(arguments.duration), "10", "-file", str(output / "stacks.txt")], capture_output=True, text=True, timeout=arguments.duration + 15)
    (output / "capture.log").write_text(result.stdout + result.stderr)
    report["sampleExitCode"] = result.returncode
    report["processAfter"] = process_rows()
    report["sameProcessStillRunning"] = any(row.split()[0] == pid for row in report["processAfter"])
    stacks = output / "stacks.txt"
    if stacks.exists():
        text = stacks.read_text(errors="replace")
        for key, label in [("physicalFootprint", "Physical footprint:"), ("peakPhysicalFootprint", "Physical footprint (peak):")]:
            match = re.search(re.escape(label) + r"\s+([^\n]+)", text)
            if match:
                report[key] = match.group(1).strip()
    (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("Regram metrics and stacks saved to " + str(output))
    if result.returncode or not report["sameProcessStillRunning"]:
        raise SystemExit("Capture incomplete; inspect capture.log and report.json.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
