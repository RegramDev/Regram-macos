import Cocoa
import TGUIKit
import InputDataUI
import RegramCore
import TelegramTheme

func regramSettingsHomeEntries(query: String, language: String, update: @escaping (String) -> Void, open: @escaping (String) -> Void) -> [InputDataEntry] {
    var builder = RegramPageBuilder(page: "pro.home")
    builder.section()
    builder.search("search", value: query, placeholder: regramString("Settings.Search.Placeholder"), update: update)
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedQuery.isEmpty {
        let groups: [[RegramCategory]] = [[.messages, .input, .translation, .media], [.privacy, .appearance, .notifications], [.network, .tools]]
        for group in groups {
            builder.section()
            for category in group where category != .notifications || RegramSettingsScope.includesNotifications {
                builder.row("category." + category.rawValue, title: regramString("Settings.ProCategory." + category.rawValue), type: .next, icon: RegramSettingsArtwork.category(category), description: regramString("Settings.ProCategory." + category.rawValue + ".Description"), action: { open("pro." + category.rawValue) })
            }
        }
        builder.section()
        builder.row("localGifts", title: regramString("Showroom.Title"), type: .next, icon: RegramSettingsArtwork.symbolImage("sparkles"), description: regramString("Showroom.Description"), action: { open("localGifts") })
    } else {
        let results = RegramSettingsCatalog.results(query: trimmedQuery, language: language)
        let grouped = Dictionary(grouping: results, by: { $0.page == "pro.home" ? "Settings.Pro.Title" : $0.pageTitleKey })
        var seen = Set<String>()
        for result in results {
            let group = result.page == "pro.home" ? "Settings.Pro.Title" : result.pageTitleKey
            guard seen.insert(group).inserted else { continue }
            builder.section(group)
            for result in grouped[group] ?? [] {
                builder.row("result." + result.sourceIdentifier, title: regramString(result.titleKey), type: .next, action: {
                    open(result.destination)
                })
            }
        }
        if results.isEmpty {
            builder.section()
            builder.custom("empty", equatable: InputDataEquatable(query), item: { size, stableId in RegramEmptyRowItem(size, stableId: stableId, height: 180, text: regramString("Settings.Search.NoResults")) })
        }
    }
    return builder.entries
}
