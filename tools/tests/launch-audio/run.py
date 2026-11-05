import argparse
from pathlib import Path

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
args = parser.parse_args()
root = args.root


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


delegate = (root / 'Telegram-Mac/app/AppDelegate.swift').read_text()
launch = section(delegate, 'func applicationDidFinishLaunching', 'launchInterface()')
devices_source = (root / 'packages/TelegramMediaUtils/Sources/TelegramMediaUtils/DevicesContext.swift').read_text()
devices = section(devices_source, 'public init(_ accountManager', '    private func update()')
listener_install = section(devices_source, '    private func installAudioListeners()', '    deinit {')
registration_source = devices + listener_install

registration = ['AudioListener.retainOutputListener()', '&AudioAddress.inputDevice', '&AudioAddress.devices']
queued = devices[devices.index('devicesQueue.async {'):] if 'devicesQueue.async {' in devices else ''
queued_block = queued[:queued.index('\n        }\n')] if queued else ''

results = {
    'launch-creates-no-audio-player': 'AVAudioPlayer(' not in launch,
    'listeners-register-off-the-main-thread': 'self.installAudioListeners()' in queued_block and all(item in listener_install for item in registration),
    'listeners-register-only-once': all(registration_source.count(item) == 1 for item in registration),
    'device-list-loads-after-registration': bool(queued) and 'update()\n    }' in queued[len(queued_block):],
}

failures = 0
for name, passed in results.items():
    failures += 0 if passed else 1
    print(f"{'PASS' if passed else 'FAIL'} {name}")
print(f'{len(results) - failures} passed; {failures} failed (production source checks; no application/UI session)')
raise SystemExit(1 if failures else 0)
