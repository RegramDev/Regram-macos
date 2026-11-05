from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
path = ROOT / "packages/ChannelAdminUI/Sources/ChannelAdminUI/ChannelEventLogController.swift"
source = path.read_text()
start = source.index("        let left =", source.index("private final class EventLogTitleBarView"))
end = source.index("        glassContainer.setGhostFrame", start)
geometry = source[start:end]
fixture = r'''
import AppKit

final class HeaderController {
    let leftBarView: NSView? = NSView(frame: NSMakeRect(0, 0, 52, 60))
    let rightBarView: NSView?
    init(width: CGFloat) { rightBarView = NSView(frame: NSMakeRect(width - 52, 0, 52, 60)) }
}

func frames(width: CGFloat, title: String, searching: Bool) -> (title: NSRect, search: NSRect, expanded: NSRect) {
    let size = NSMakeSize(width, 60)
    let controller: HeaderController? = HeaderController(width: width)
    let text: NSAttributedString? = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 14)])
    let status: NSAttributedString? = NSAttributedString(string: "Recent Actions", attributes: [.font: NSFont.systemFont(ofSize: 11)])
__GEOMETRY__
    return (titleRect, searchRect, expandedSearchRect)
}

_ = NSApplication.shared
var checks = 0
func check(_ condition: @autoclosure () -> Bool) { checks += 1; precondition(condition()) }
for width: CGFloat in [380, 420, 600, 900, 1200] {
    for title in ["Chat", "最近操作", "Recent Actions in a channel with a very long display name", "القناة"] {
        let closed = frames(width: width, title: title, searching: false)
        let opened = frames(width: width, title: title, searching: true)
        check(closed.title == opened.title)
        check(opened.title.minX == 62)
        check(opened.title.minY == 10 && opened.title.height == 40)
        check(opened.title.width >= 40 && opened.title.width <= 260)
        check(abs(opened.search.minX - opened.title.maxX - 10) < 0.01)
        check(abs(opened.search.maxX - (width - 62)) < 0.01)
        check(opened.search.width >= 160)
        check(opened.search == opened.expanded)
        check(closed.search.width == 40)
        check(abs(closed.search.maxX - (width - 62)) < 0.01)
    }
}
print("Recent Actions header geometry: \(checks) checks passed")
'''.replace("__GEOMETRY__", geometry)

with tempfile.TemporaryDirectory(prefix="recent-actions-header-") as directory:
    directory = Path(directory)
    swift = directory / "main.swift"
    swift.write_text(fixture)
    binary = directory / "checks"
    subprocess.run(["xcrun", "swiftc", "-O", "-DSTABLE", str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print(json.dumps({"source": str(path.relative_to(ROOT)), "sha256": hashlib.sha256(source.encode()).hexdigest(), "scope": "Unchanged production geometry with real AppKit text measurement; synthetic bars. No installed application, recording or live account actions."}))
