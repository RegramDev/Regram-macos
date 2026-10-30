import RegramCore

struct RegramComposerRefresh: OptionSet, Equatable {
    let rawValue: Int
    static let context = RegramComposerRefresh(rawValue: 1)
    static let preview = RegramComposerRefresh(rawValue: 2)
}

struct RegramComposerPreferences: Equatable {
    static let preferenceKeys: Set<String> = ["features.autoInlineBotEnabled", "disableLinkPreview", "fixLinkPreviews", "linkPreviewXHost", "linkPreviewInstagramHost"]
    let automaticInlineBots: Bool
    let preview: [RegramValue]

    init(settings: RegramAccountSettings) {
        automaticInlineBots = settings["features.autoInlineBotEnabled"].bool
        preview = ["disableLinkPreview", "fixLinkPreviews", "linkPreviewXHost", "linkPreviewInstagramHost"].map { settings[$0] }
    }

    func changes(from previous: RegramComposerPreferences) -> RegramComposerRefresh {
        var changes: RegramComposerRefresh = []
        if automaticInlineBots != previous.automaticInlineBots { changes.insert(.context) }
        if preview != previous.preview { changes.insert(.preview) }
        return changes
    }
}

struct RegramComposerRefreshState {
    private var previous: RegramComposerPreferences?
    private var pending: RegramComposerRefresh = []

    mutating func update(_ preferences: RegramComposerPreferences, visible: Bool) -> (cancel: RegramComposerRefresh, reload: RegramComposerRefresh) {
        let changes = previous.map { preferences.changes(from: $0) } ?? []
        previous = preferences
        pending.formUnion(changes)
        let reload: RegramComposerRefresh = visible ? pending : []
        if visible { pending = [] }
        return (changes, reload)
    }
}
