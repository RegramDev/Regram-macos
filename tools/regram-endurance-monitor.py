from pathlib import Path
import argparse
import ctypes
from datetime import datetime
import fcntl
import json
import plistlib
import subprocess
import time
from zoneinfo import ZoneInfo


APP = Path("/Applications/Regram.app")
EXECUTABLE = APP / "Contents/MacOS/Regram"
MAX_RECORDS = 2048


class TaskInfo(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in ["virtual_size", "resident_size", "total_user", "total_system", "threads_user", "threads_system"]] + [(name, ctypes.c_int32) for name in ["policy", "faults", "pageins", "cow_faults", "messages_sent", "messages_received", "syscalls_mach", "syscalls_unix", "context_switches", "thread_count", "running_threads", "priority"]]


class ResourceUsage(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(name, ctypes.c_uint64) for name in ["user_time", "system_time", "package_idle_wakeups", "interrupt_wakeups", "pageins", "wired_size", "resident_size", "physical_footprint", "process_start", "process_exit", "child_user_time", "child_system_time", "child_package_idle_wakeups", "child_interrupt_wakeups", "child_pageins", "child_elapsed", "disk_read", "disk_written"]]


def process_metrics():
    library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    library.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    library.proc_pidpath.restype = ctypes.c_int
    library.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
    library.proc_pidinfo.restype = ctypes.c_int
    library.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    library.proc_pid_rusage.restype = ctypes.c_int
    candidates = subprocess.run(["pgrep", "-x", "Regram"], capture_output=True, text=True, timeout=3)
    if candidates.returncode not in [0, 1]:
        raise RuntimeError("Cannot list Regram processes: " + candidates.stderr.strip())
    records = []
    for value in candidates.stdout.split():
        pid = int(value)
        path = ctypes.create_string_buffer(4096)
        if library.proc_pidpath(pid, path, len(path)) <= 0 or Path(path.value.decode()) != EXECUTABLE:
            continue
        task = TaskInfo()
        usage = ResourceUsage()
        if library.proc_pidinfo(pid, 4, 0, ctypes.byref(task), ctypes.sizeof(task)) != ctypes.sizeof(task):
            raise OSError(ctypes.get_errno(), "Cannot read Regram task counters")
        if library.proc_pid_rusage(pid, 2, ctypes.byref(usage)) != 0:
            raise OSError(ctypes.get_errno(), "Cannot read Regram resource counters")
        records.append({"pid": pid, "processStart": usage.process_start, "executableUUID": bytes(usage.uuid).hex(), "physicalFootprintBytes": usage.physical_footprint, "residentBytes": usage.resident_size, "virtualBytes": task.virtual_size, "threads": task.thread_count, "runningThreads": task.running_threads, "userTimeRaw": usage.user_time, "systemTimeRaw": usage.system_time, "pageins": usage.pageins, "idleWakeups": usage.package_idle_wakeups, "interruptWakeups": usage.interrupt_wakeups, "diskReadBytes": usage.disk_read, "diskWrittenBytes": usage.disk_written})
    return records


def capture():
    records = process_metrics()
    info = plistlib.loads((APP / "Contents/Info.plist").read_bytes()) if APP.exists() else {}
    pressure = subprocess.run(["sysctl", "-n", "kern.memorystatus_vm_pressure_level"], capture_output=True, text=True, timeout=3)
    swap = subprocess.run(["sysctl", "vm.swapusage"], capture_output=True, text=True, timeout=3)
    return {"capturedAt": datetime.now(ZoneInfo("Asia/Singapore")).isoformat(timespec="seconds"), "monotonicTime": time.monotonic(), "build": info.get("CFBundleVersion"), "running": bool(records), "processes": records, "systemPressureLevel": pressure.stdout.strip() or None, "systemSwap": swap.stdout.strip() or None, "accountContentRead": False, "applicationRestarted": False}


def collect(output, samples, interval):
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.with_suffix(output.suffix + ".lock").open("a") as session:
        try:
            fcntl.flock(session, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit("An endurance collector is already writing this output")
        for index in range(samples):
            record = capture()
            lines = output.read_text().splitlines()[-(MAX_RECORDS - 1):] if output.exists() else []
            lines.append(json.dumps(record, ensure_ascii=False))
            temporary = output.with_suffix(output.suffix + ".tmp")
            temporary.write_text("\n".join(lines) + "\n")
            temporary.replace(output)
            print(json.dumps(record, ensure_ascii=False), flush=True)
            if index + 1 < samples:
                time.sleep(interval)


def main():
    parser = argparse.ArgumentParser(description="Read bounded Regram process resource metrics without accessing account content or restarting the application")
    parser.add_argument("--output", type=Path, default=Path.home() / "Library/Logs/RegramPerformance/endurance/metrics.jsonl")
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument("--interval", type=int, default=60)
    args = parser.parse_args()
    if not 1 <= args.samples <= 60 or not 5 <= args.interval <= 60:
        parser.error("samples must be 1..60 and interval 5..60 seconds")
    collect(args.output, args.samples, args.interval)


if __name__ == "__main__":
    main()
