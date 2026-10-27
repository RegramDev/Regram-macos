final class FixtureChat: ViewController, SettingsChatController {
    let mode: ChatMode
    let chatLocation: ChatLocation
    init(_ peerId: Int64, mode: ChatMode = .history) {
        self.mode = mode
        self.chatLocation = ChatLocation(peerId: peerId)
    }
}

let harness = SelectionHarness()
var count = 0
func check(_ stack: [ViewController], _ selected: Int?, _ label: String) {
    let navigation = MajorNavigationController(stack)
    harness.navigation = navigation
    harness.tableView.selected = AnyHashable(AccountInfoEntryId.index(-100))
    harness.navigationWillChangeController()
    let expected = selected.map { AnyHashable(AccountInfoEntryId.index($0)) }
    precondition(harness.tableView.selected == expected, label)
    count += 1
}

check([FixtureChat(42)], -101, "Saved Messages selects its sidebar row")
check([FixtureChat(42, mode: .thread)], -101, "Saved Messages thread keeps selection")
check([FixtureChat(42, mode: .scheduled)], -101, "Saved Messages scheduled view keeps selection")
check([FixtureChat(43)], nil, "Another chat clears stale selection")
check([FixtureChat(42, mode: .customChatContents)], 20, "Business custom contents keep native selection")
check([FixtureChat(42, mode: .customLink)], 20, "Business custom links keep native selection")
check([InputDataController("regram.bookmarks")], -102, "Bookmarks selects its own row")
check([InputDataController("regram.bookmarks.tags")], -102, "Bookmark subpages keep selection")
check([InputDataController("regram.bookmarks"), FixtureChat(43)], -102, "Opening a bookmark keeps originating settings selection")
check([InputDataController("regram.pro.home")], -100, "Regram home selects Pro")
check([InputDataController("regram.messages")], -100, "Message settings select Pro")
check([InputDataController("regram.pro.home"), InputDataController("regram.bookmarks")], -102, "Nearest bookmark page takes priority")
check([InputDataController("regram.bookmarks"), InputDataController("regram.messages")], -100, "Nearest Pro page takes priority")
check([InputDataController("regram.pro.home")], -100, "Returning to Pro restores selection")
check([GeneralSettingsViewController<FixtureContext>()], 7, "General settings retain native selection")
check([InputDataController("language")], 13, "Language retains native selection")
check([InputDataController("unknown")], nil, "Unrelated settings clear selection")
check([InputDataController("regram.bookmarksExtra")], -100, "Similar page names are not bookmark pages")

harness.tableView.rows.removeValue(forKey: AnyHashable(AccountInfoEntryId.index(-102)))
check([InputDataController("regram.bookmarks")], nil, "Removed bookmark row clears selection")
check([FixtureChat(42)], -101, "Saved Messages still selects while bookmarks are hidden")
check([InputDataController("regram.messages")], -100, "The enabling switch remains under Pro")
harness.tableView.rows[AnyHashable(AccountInfoEntryId.index(-102))] = FixtureRow(.index(-102))
check([InputDataController("regram.bookmarks")], -102, "Reenabled bookmark row selects again")
print("Settings navigation production-method checks passed: \(count)")
