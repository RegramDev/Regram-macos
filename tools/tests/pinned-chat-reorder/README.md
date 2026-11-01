# Pinned chat order regression

Run `python3 tools/tests/pinned-chat-reorder/run.py` from the repository root. The runner compiles Release/STABLE and extracts the ordinary chat/folder branch of the production `resortPinned` method.

The six tests cover moving up/down while retaining hidden and unloaded pinned chats, missing reference rows, root/archive/folder destinations, removed pins and no-op moves. Table rows and engine reads/writes are controlled fixtures; SwiftSignalKit executes the production signal chain. The suite does not reorder a real account or cover forum topic reordering.
