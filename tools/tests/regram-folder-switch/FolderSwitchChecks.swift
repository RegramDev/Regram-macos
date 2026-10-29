import Cocoa
import QuartzCore
import SwiftSignalKit
import TGUIKit

struct FixturePeerId { let value: Int64; func toInt64() -> Int64 { value } }
enum ChatListFilter: Equatable { case allChats, folder(Int32); var id: Int32 { if case let .folder(id) = self { return id }; return -1 } }
enum ChatListIndexRequest: Equatable { case Initial(Int, Int?), Index(Int, Int?) }
struct ChatListFilterBadges: Equatable { let total: Int; let filters: [Int] }
struct ChatListUIHooks {
    static let shared = ChatListUIHooks()
    func chatListFilterId(_ filter: ChatListFilter?) -> Int32 { filter?.id ?? -1 }
}
PRODUCTION_FILTER_DATA

struct PeerListState: Equatable { var filterData: FilterData; var noise = 0 }
final class FixtureNavigation { var backs = 0; var closes = 0; func back() { backs += 1 }; func close(animated: Bool) { closes += 1 } }
enum FixtureScroll: Equatable { case up(Bool) }
final class FixtureTable {
    var scrolls: [(FixtureScroll, Bool)] = []
    var documentOffset = NSPoint.zero
    func scroll(to: FixtureScroll, ignoreLayerAnimation: Bool = false) { scrolls.append((to, ignoreLayerAnimation)) }
}
enum FixtureSearchState { case None }
final class FixtureSearch { var clears = 0; func change(state: FixtureSearchState, _ animated: Bool) { clears += 1 } }
final class FixtureGenericView { let tableView = FixtureTable(); let searchView = FixtureSearch(); let navigationHeight: CGFloat = 0 }
final class FixturePeers {
    var polls: [Int32] = []
    var activePolls = 0
    func pollChatFolderUpdates(folderId: Int32) -> Signal<Never, NoError> {
        Signal { subscriber in
            self.polls.append(folderId)
            self.activePolls += 1
            return ActionDisposable { self.activePolls -= 1 }
        }
    }
}
final class FixtureEngine { let peers = FixturePeers() }
final class FixtureMain {
    var chatList: ChatListController!
    let navigation = FixtureNavigation()
    var reveals = 0
    func showChatList() { reveals += 1 }
}
final class FixtureBindings {
    let mainViewController = FixtureMain()
    let root = FixtureNavigation()
    func rootNavigation() -> FixtureNavigation { root }
}
final class FixtureAccount { let id: Int64; init(_ id: Int64) { self.id = id } }
final class AccountContext {
    var isPremium = true
    let premiumLimits = (dialog_filters_limit_default: 1, unused: 0)
    var window = (frame: NSRect(x: 0, y: 0, width: 600, height: 700), unused: 0)
    let peerId: FixturePeerId
    let account: FixtureAccount
    let bindings = FixtureBindings()
    let engine = FixtureEngine()
    var layout: SplitViewState = .single
    var premiumPrompts = 0
    init(_ id: Int64) { peerId = FixturePeerId(value: id); account = FixtureAccount(id) }
}
enum FixturePremiumLimit { case folders }
struct FeatureNavigationHooks {
    static let shared = FeatureNavigationHooks()
    func showPremiumLimit(_ context: AccountContext, _ limit: FixturePremiumLimit) { context.premiumPrompts += 1 }
}
enum RegramChatListPolicy {
    static var selected: [(Int32, Int64)] = []
    static func recordSelectedFolderId(_ id: Int32, accountId: Int64) { selected.append((id, accountId)) }
}
class PeersListController {
    let context: AccountContext
    let stateValue: Atomic<PeerListState>
    let stateSignal: ValuePromise<PeerListState>
    let navigationController: FixtureNavigation? = FixtureNavigation()
    let genericView = FixtureGenericView()
    var filterSignal: Signal<FilterData, NoError> { stateSignal.get() |> map { $0.filterData } }
    var filterValue: FilterData { stateValue.with { $0.filterData } }
    var state: PeerListState? { stateValue.with { $0 } }
    init(_ context: AccountContext, _ data: FilterData) {
        self.context = context
        stateValue = Atomic(value: PeerListState(filterData: data))
        stateSignal = ValuePromise(PeerListState(filterData: data), ignoreRepeated: true)
    }
    func scrollup(force: Bool = false) { genericView.tableView.scroll(to: .up(true), ignoreLayerAnimation: force) }
    PRODUCTION_BASE_UPDATE
    PRODUCTION_BASE_SELECT
    func topAction() -> (ChatListFilter) -> Void { return PRODUCTION_TOP_ROUTE }
    func archiveSignal() -> Signal<EngineChatList.GroupItem?, NoError> {
        let context = self.context
        let filterSignal = self.filterSignal
        PRODUCTION_ARCHIVE
    }
}
final class ChatListController: PeersListController {
    private let folderUpdatesDisposable = MetaDisposable()
    var revealClears = 0
    var titleSets = 0
    let defaultBarTitle = "fixture"
    func removeRevealStateIfNeeded(_ value: Int?) { revealClears += 1 }
    func setCenterTitle(_ value: String) { titleSets += 1 }
    var page: FixturePaginationView?
    func paginationView() -> FixturePaginationView? { page }
    func scrollAction() -> (FixtureScrollPosition) -> Void {
        let regramRestingNearTop = Atomic(value: true)
        let animated = Atomic(value: false)
        return PRODUCTION_CHAT_SCROLL
    }
    PRODUCTION_CHAT_SELECT
    PRODUCTION_CHAT_UPDATE
    deinit { folderUpdatesDisposable.dispose() }
}
PRODUCTION_SIDEBAR_ROUTE

struct FixtureValue { let bool: Bool }
struct FixtureSettings: Equatable {
    var show = false
    var hide = false
    var unrelated = 0
    subscript(_ key: String) -> FixtureValue { FixtureValue(bool: key == "features.showArchiveInFolders" ? show : hide) }
}
enum FixturePreferences {
    static var values: [Int64: ValuePromise<FixtureSettings>] = [:]
    static func value(_ id: Int64) -> ValuePromise<FixtureSettings> {
        if let value = values[id] { return value }
        let value = ValuePromise(FixtureSettings(), ignoreRepeated: false)
        values[id] = value
        return value
    }
}
func regramPreferenceChanges(accountId: Int64) -> Signal<FixtureSettings, NoError> { FixturePreferences.value(accountId).get() }
enum EngineChatList {
    enum Group: Equatable { case archive }
    struct GroupItem: Equatable { let id: Group; let version: Int }
    struct Item { typealias Index = Int; let index: Index }
}
struct FixturePaginationView { let items: [EngineChatList.Item]; let hasEarlier: Bool; let hasLater: Bool }
struct FixtureScrollPosition { let direction: ScrollDirection }
let nativePagingCount = NATIVE_PAGING_COUNT
struct FixtureList { let groupItems: [EngineChatList.GroupItem] }
struct FixtureUpdate { let list: FixtureList }
enum FixtureLocation { case chatList(groupId: FixtureGroup) }
enum FixtureGroup { case root }
final class FixtureArchive {
    static var sources: [Int64: FixtureArchive] = [:]
    let pipe = ValuePipe<FixtureUpdate>()
    var starts = 0
    var stops = 0
    var active = 0
    static func source(_ id: Int64) -> FixtureArchive {
        if let source = sources[id] { return source }
        let source = FixtureArchive(); sources[id] = source; return source
    }
    func signal() -> Signal<FixtureUpdate, NoError> {
        Signal { subscriber in
            self.starts += 1; self.active += 1
            let disposable = self.pipe.signal().start(next: subscriber.putNext)
            subscriber.putNext(FixtureUpdate(list: FixtureList(groupItems: [.init(id: .archive, version: self.starts)])))
            return ActionDisposable { disposable.dispose(); self.active -= 1; self.stops += 1 }
        }
    }
    func emit(_ version: Int) { pipe.putNext(FixtureUpdate(list: FixtureList(groupItems: [.init(id: .archive, version: version)]))) }
}
func chatListViewForLocation(chatListLocation: FixtureLocation, location: ChatListIndexRequest, filter: ChatListFilter?, account: FixtureAccount) -> Signal<FixtureUpdate, NoError> {
    precondition(location == .Initial(1, nil) && filter == .allChats)
    return FixtureArchive.source(account.id).signal()
}

final class FixtureHeaderItem {
    let height: CGFloat = 30
    var count = 20
    var selected = 12
    var dark = false
}
final class ChatListRevealView: NSView {
    let containerView = View()
    let segmentView = ScrollableSegmentView(frame: .zero)
    private var segmentItems: [ScrollableSegmentItem] = []
    var sets = 0
    var labelBuilds = 0
    var item: FixtureHeaderItem?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(containerView)
        containerView.addSubview(segmentView)
    }
    required init?(coder: NSCoder) { fatalError() }
    func set(item: FixtureHeaderItem, animated: Bool) {
        sets += 1
        self.item = item
        let theme = ScrollableSegmentTheme(background: .clear, border: .gray, selector: .systemBlue, inactiveText: item.dark ? .lightGray : .darkGray, activeText: item.dark ? .white : .black, textFont: .systemFont(ofSize: 13))
        segmentView.theme = theme
        segmentView.fitToWidth = true
        let items = (0..<item.count).map { index in ScrollableSegmentItem(title: "Folder \(index)", index: index, uniqueId: Int64(index), selected: index == item.selected, insets: NSEdgeInsets(left: 14, right: 14), icon: nil, theme: theme, equatable: nil, customTextView: { [weak self] in
            self?.labelBuilds += 1
            return NSView(frame: NSRect(x: 0, y: 0, width: 65, height: 16))
        }) }
        PRODUCTION_SEGMENT_BINDING
    }
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {}
    PRODUCTION_HEADER_LAYOUT
}
final class FixtureHeaderContainer: NSView {
    let containerView = NSView()
    let statusContainer = NSView()
    var foldersItem: FixtureHeaderItem? = FixtureHeaderItem()
    var foldersView: ChatListRevealView?
    let navigationHeight: CGFloat = 80
    var regramFoldersAtBottom = false
    let contentBottomInset: CGFloat = 40
    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(containerView)
        containerView.addSubview(statusContainer)
    }
    required init?(coder: NSCoder) { fatalError() }
    func apply(animated: Bool = false) {
        PRODUCTION_HEADER_APPLY
    }
    func geometry(_ size: NSSize, transition: ContainedViewLayoutTransition = .immediate) {
        PRODUCTION_HEADER_GEOMETRY
        foldersView?.layout()
        foldersView?.segmentView.layout()
    }
}

@main
struct FolderSwitchChecks {
    static var count = 0
    static var failures: [String] = []
    static var observations: [[String: Any]] = []
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        count += 1
        if !value() { failures.append(label); print("FAIL \(label)") }
    }
    static func make(_ id: Int64, filter: ChatListFilter = .folder(1)) -> ChatListController {
        let context = AccountContext(id)
        let controller = ChatListController(context, FilterData(filter: filter, tabs: [.allChats, .folder(1), .folder(2), .folder(3)], request: .Index(900, nil), requestTimestamp: 1, isTop: false))
        context.bindings.mainViewController.chatList = controller
        return controller
    }
    static func routeChecks() {
        let top = make(11)
        var snapshots: [FilterData] = []
        let observation = top.filterSignal.start(next: { snapshots.append($0) })
        snapshots.removeAll()
        RegramChatListPolicy.selected.removeAll()
        top.topAction()(.folder(2))
        check(snapshots.count == 1, "top changed folder emits one state")
        check(snapshots.first?.filter == .folder(2), "first state already selects B")
        check(snapshots.first?.request == .Initial(nativePagingCount, nil), "first B request uses native paging capacity")
        check(snapshots.first?.isTop == true, "B isTop resets with request")
        check(top.context.engine.peers.polls == [2] && top.context.engine.peers.activePolls == 1, "top starts one target folder poll")
        check(RegramChatListPolicy.selected.map { $0.0 } == [2], "top remembers chosen folder")
        check(top.genericView.searchView.clears == 1 && top.revealClears == 1, "top clears search and reveal once")
        check(top.genericView.tableView.scrolls.count == 1 && !top.genericView.tableView.scrolls[0].1, "changed folder scrolls once through updateFilter")
        check(top.navigationController?.backs == 1, "top retains navigation back")
        observations.append(["stage": "top A to B", "stateEmissions": snapshots.count, "request": String(describing: top.filterValue.request), "pollStarts": top.context.engine.peers.polls.count, "scrolls": top.genericView.tableView.scrolls.count, "searchClears": top.genericView.searchView.clears])
        let sidebar = make(12)
        navigateToChatListFilter(2, context: sidebar.context)
        check(sidebar.filterValue.request == top.filterValue.request && sidebar.filterValue.filter == top.filterValue.filter, "top and Sidebar share filter/request semantics")
        check(sidebar.context.engine.peers.polls == top.context.engine.peers.polls, "top and Sidebar share target polling")
        snapshots.removeAll()
        let polls = top.context.engine.peers.polls.count
        let scrolls = top.genericView.tableView.scrolls.count
        top.topAction()(.folder(2))
        check(snapshots.isEmpty, "same folder does not emit/restart data")
        check(top.context.engine.peers.polls.count == polls, "same folder does not restart poll")
        check(top.genericView.tableView.scrolls.count == scrolls + 1 && top.genericView.tableView.scrolls.last?.1 == true, "same folder preserves forced scroll")
        let denied = make(13)
        denied.context.isPremium = false
        var deniedSnapshots = 0
        let deniedObservation = denied.filterSignal.start(next: { _ in deniedSnapshots += 1 })
        deniedSnapshots = 0
        denied.topAction()(.folder(3))
        check(denied.context.premiumPrompts == 1 && deniedSnapshots == 0, "top obeys native premium gate before data mutation")
        check(denied.context.engine.peers.polls.isEmpty && denied.genericView.tableView.scrolls.isEmpty, "denied selection has no query/poll/scroll effects")
        top.topAction()(.folder(3)); top.topAction()(.folder(1))
        check(top.filterValue.filter == .folder(1) && top.filterValue.request == .Initial(nativePagingCount, nil), "rapid changes settle on latest folder and tail")
        check(top.context.engine.peers.activePolls == 1, "rapid changes cancel previous folder poll")
        top.topAction()(.allChats)
        check(top.context.engine.peers.polls.last == -1 && RegramChatListPolicy.selected.last?.0 == -1, "All Chats uses canonical saved/poll id")
        observation.dispose(); deniedObservation.dispose()
    }
    static func scrollChecks() {
        check(FilterData().request == .Initial(nativePagingCount, nil), "startup uses native paging capacity")
        for height in [350, 700, 1400, 2800] {
            let controller = make(Int64(100 + height))
            controller.context.window.frame.size.height = CGFloat(height)
            controller.selectFilter(.folder(2))
            check(controller.filterValue.request == .Initial(nativePagingCount, nil), "folder initial capacity is stable at height \(height)")
        }
        let idle = make(51)
        var transforms = 0
        var emissions = 0
        let observation = idle.filterSignal.start(next: { _ in emissions += 1 })
        emissions = 0
        for _ in 0..<500 {
            idle.updateFilter { transforms += 1; return $0.withUpdatedIsTop(false) }
        }
        check(transforms == 500, "unchanged scroll state avoids a second transform")
        check(emissions == 0 && idle.titleSets == 0, "unchanged scroll state avoids title and signal work")
        idle.updateFilter { $0.withUpdatedBadges(.init(total: 10, filters: [1])) }
        check(emissions == 1 && idle.titleSets == 0, "changed badges still publish without rebuilding title")
        observation.dispose()

        let duplicate = make(52)
        duplicate.page = FixturePaginationView(items: [.init(index: 900)], hasEarlier: true, hasLater: false)
        let samePage = duplicate.scrollAction()
        var duplicateEmissions = 0
        let duplicateObservation = duplicate.filterSignal.start(next: { _ in duplicateEmissions += 1 })
        duplicateEmissions = 0
        for _ in 0..<500 { samePage(FixtureScrollPosition(direction: .bottom)) }
        check(duplicateEmissions == 0 && duplicate.titleSets == 0, "same page cursor does not trigger repeated list preparation")
        duplicateObservation.dispose()
        let next = make(53)
        next.page = FixturePaginationView(items: [.init(index: 800)], hasEarlier: true, hasLater: false)
        next.scrollAction()(FixtureScrollPosition(direction: .bottom))
        check(next.filterValue.request == .Index(800, nil), "new page cursor still loads immediately")
        check(!next.filterValue.isTop && next.titleSets == 0, "pagination preserves state without rebuilding unchanged title")

        for available in [0, 5, 80, 500] {
            let controller = make(Int64(200 + available))
            controller.selectFilter(.folder(2))
            guard case let .Initial(capacity, _) = controller.filterValue.request else {
                check(false, "expected initial folder request")
                continue
            }
            var loaded = min(available, capacity)
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 640))
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.scrollerStyle = .legacy
            let document = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: loaded * 70))
            scroll.documentView = document
            scroll.tile()
            scroll.reflectScrolledClipView(scroll.contentView)
            let before = scroll.verticalScroller!.knobProportion
            let offset = min(CGFloat(420), max(0, document.frame.height - scroll.contentSize.height))
            let bounds = scroll.contentView.bounds.offsetBy(dx: 0, dy: offset)
            scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(bounds).origin)
            let visibleEnd = min(loaded, Int(ceil((offset + scroll.contentSize.height) / 70)))
            if loaded > 0, loaded - visibleEnd <= loaded / 6, loaded < available {
                controller.page = FixturePaginationView(items: [.init(index: 1)], hasEarlier: true, hasLater: false)
                controller.scrollAction()(FixtureScrollPosition(direction: .bottom))
                if case .Index = controller.filterValue.request {
                    loaded = min(available, loaded + nativePagingCount)
                    document.setFrameSize(NSSize(width: 280, height: loaded * 70))
                }
            }
            scroll.reflectScrolledClipView(scroll.contentView)
            let after = scroll.verticalScroller!.knobProportion
            check(abs(before - after) < 0.0001, "native scrollbar is stable on first short scroll for \(available) chats")
            check(loaded == min(available, nativePagingCount), "first short scroll does not expand initial page for \(available) chats")
            if available >= 80 {
                check(before > 0 && before < 0.3, "native scrollbar starts small for \(available) chats")
            }
            observations.append(["stage": "first folder scroll", "available": available, "initialCapacity": capacity, "beforeKnob": before, "afterKnob": after, "loadedAfterScroll": loaded])
        }
    }
    static func archiveChecks() {
        let controller = make(21)
        let source = FixtureArchive.source(21)
        var received: [Int?] = []
        let disposable = controller.archiveSignal().start(next: { received.append($0?.version) })
        check(received.count == 1 && received[0] == nil && source.starts == 0, "disabled archive emits one nil without query")
        for index in 0..<40 {
            controller.updateState { var state = $0; state.noise = index + 1; return state }
            FixturePreferences.value(21).set(FixtureSettings(unrelated: index))
        }
        check(received.count == 1 && source.starts == 0, "unrelated state/preferences do not re-emit disabled archive")
        observations.append(["stage": "archive disabled after 40 state and 40 preference updates", "emissions": received.count, "queryStarts": source.starts])
        controller.topAction()(.folder(2))
        check(received.count == 1, "disabled archive ignores custom-folder selection")
        FixturePreferences.value(21).set(FixtureSettings(show: true))
        check(source.starts == 1 && source.active == 1 && received.last! == 1, "enabling archive starts one current-account subscription")
        let receivedBeforeNoise = received.count
        for index in 0..<40 {
            controller.updateState { var state = $0; state.noise += 1; return state }
            FixturePreferences.value(21).set(FixtureSettings(show: true, unrelated: index))
        }
        controller.topAction()(.folder(3))
        check(source.starts == 1 && source.stops == 0 && received.count == receivedBeforeNoise, "enabled archive survives unrelated state and A-to-B without restart")
        observations.append(["stage": "archive enabled after 40 state and 40 preference updates and folder change", "queryStarts": source.starts, "queryStops": source.stops, "active": source.active, "extraEmissions": received.count - receivedBeforeNoise])
        source.emit(77)
        check(received.last! == 77, "real archive updates remain live")
        controller.topAction()(.allChats)
        check(source.active == 0 && source.stops == 1 && received.last! == nil, "All Chats cancels archive and clears row")
        controller.topAction()(.folder(1))
        check(source.active == 1 && source.starts == 2, "leaving All Chats starts one new archive subscription")
        FixturePreferences.value(21).set(FixtureSettings(show: true, hide: true))
        check(source.active == 0 && received.last! == nil, "hide saved/archive setting cancels archive")
        FixturePreferences.value(21).set(FixtureSettings(show: true))
        check(source.active == 1 && source.starts == 3, "unhiding restores archive subscription")
        let other = make(22)
        FixturePreferences.value(22).set(FixtureSettings(show: true))
        let otherSource = FixtureArchive.source(22)
        var otherReceived: [Int?] = []
        let otherDisposable = other.archiveSignal().start(next: { otherReceived.append($0?.version) })
        source.emit(88)
        check(otherSource.active == 1 && otherSource.starts == 1 && otherReceived.last! == 1, "separate account has separate archive source")
        disposable.dispose(); otherDisposable.dispose()
        check(source.active == 0 && otherSource.active == 0, "archive disposal releases each account subscription")
    }
    static func headerChecks() {
        let container = FixtureHeaderContainer(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        container.apply(); container.geometry(container.frame.size)
        let view = container.foldersView!
        check(view.sets == 1, "content application plus geometry calls header.set once")
        for dark in [false, true] {
            container.foldersItem!.dark = dark
            container.apply()
            let sets = view.sets
            let labels = view.labelBuilds
            for width: CGFloat in [1000, 600, 320, 600, 1000] {
                container.frame.size.width = width
                container.geometry(container.frame.size)
                check(view.sets == sets, "width \(width) dark \(dark) performs geometry without header.set")
                check(view.labelBuilds == labels, "width \(width) dark \(dark) reuses native labels")
                check(view.frame.width == width && view.segmentView.frame.width == width, "native header width tracks \(width) dark \(dark)")
                let cells = view.segmentView.scrollView.documentView!.subviews
                check(cells.count == 20, "resize retains native cells \(width) dark \(dark)")
                let selected = cells[container.foldersItem!.selected]
                let rect = view.segmentView.convert(selected.bounds, from: selected)
                check(rect.intersects(view.segmentView.bounds), "selected tab remains visible after \(width) dark \(dark)")
                observations.append(["stage": "native header resize", "width": width, "dark": dark, "headerSets": view.sets, "labelFactories": view.labelBuilds, "selectedMinX": rect.minX, "selectedMaxX": rect.maxX])
            }
        }
        let labels = view.labelBuilds
        container.foldersItem!.selected = 17
        container.apply(); container.geometry(container.frame.size)
        check(view.labelBuilds == labels + 2, "selection recreates only the two changed native labels")
        let previousLabels = view.labelBuilds
        container.apply(); container.geometry(NSSize(width: 320, height: 500))
        check(view.labelBuilds == previousLabels, "equal content and narrow resize reuse label identities")
        view.isHidden = true
        container.geometry(NSSize(width: 600, height: 500))
        view.isHidden = false
        container.geometry(NSSize(width: 320, height: 500))
        let selected = view.segmentView.scrollView.documentView!.subviews[17]
        check(view.segmentView.convert(selected.bounds, from: selected).intersects(view.segmentView.bounds), "hidden and reshown header keeps selected tab visible")
        check(view.labelBuilds == previousLabels, "hide and show with resize do not rebuild native labels")
        container.regramFoldersAtBottom = true
        container.geometry(container.frame.size)
        check(view.superview === container && view.frame.minY == 430, "footer placement retains bottom inset")
        container.regramFoldersAtBottom = false
        container.geometry(container.frame.size)
        check(view.superview === container.containerView && view.frame.minY == 50, "header placement retains navigation geometry")
        let empty = FixtureHeaderContainer(frame: NSRect(x: 0, y: 0, width: 320, height: 500))
        empty.foldersItem!.count = 0
        empty.apply(); empty.geometry(empty.frame.size)
        check(empty.foldersView!.segmentView.scrollView.documentView!.subviews.isEmpty, "initial empty header lays out without cells or recursion")
        empty.foldersItem!.count = 20
        empty.apply(); empty.geometry(empty.frame.size)
        let restored = empty.foldersView!.segmentView.scrollView.documentView!.subviews[12]
        check(empty.foldersView!.segmentView.convert(restored.bounds, from: restored).intersects(empty.foldersView!.segmentView.bounds), "empty header later binds and reveals selected native tab")
        check(!NSApp.windows.contains { $0.isVisible }, "fixture shows no windows")
    }
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        routeChecks(); scrollChecks(); archiveChecks(); headerChecks()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let report: [String: Any] = ["checks": count, "failures": failures, "observations": observations, "productionCallbacks": true, "nativeScrollableSegmentView": true, "visibleWindows": NSApp.windows.filter { $0.isVisible }.count]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("report.json"))
        print("folder switch checks=\(count), failures=\(failures.count)")
        if !failures.isEmpty { exit(1) }
    }
}
