import XCTest
@testable import RegramCore

final class RegramNetworkAppearanceTests: XCTestCase {
    func testNetworkModeMutualExclusionAndInvalidCustomEndpointFailsClosed() {
        var settings = RegramAccountSettings()
        settings["customDoHEnabled"] = .bool(true)
        settings["localDNSForProxyHost"] = .bool(true)
        settings["customDoHEndpoint"] = .string("http://resolver.example/dns-query")
        var policy = RegramNetworkPolicy(settings: settings)
        XCTAssertEqual(policy.dnsMode, .custom)
        XCTAssertEqual(policy.effectiveEndpoint, "invalid-doh-endpoint")
        policy.dnsMode = .system
        policy.apply(to: &settings)
        XCTAssertFalse(settings["customDoHEnabled"].bool)
        XCTAssertTrue(settings["localDNSForProxyHost"].bool)
        XCTAssertNil(RegramNetworkPolicy(settings: settings).effectiveEndpoint)
        policy.dnsMode = .automatic
        policy.apply(to: &settings)
        XCTAssertFalse(settings["customDoHEnabled"].bool)
        XCTAssertFalse(settings["localDNSForProxyHost"].bool)
        XCTAssertEqual(RegramNetworkPolicy.IPVersion.ipv4Only.rawValue, 1)
        XCTAssertEqual(RegramNetworkPolicy.IPVersion.ipv6Only.rawValue, 2)
    }

    func testCustomResolverEndpointValidation() {
        XCTAssertTrue(RegramNetworkPolicy.validEndpoint(" https://resolver.example:8443/dns-query "))
        for endpoint in ["http://resolver.example", "https://user:password@resolver.example", "https://resolver.example/dns-query?name=x", "https://resolver.example/#fragment", "https://resolver.example:0", "https://resolver.example:65536", "https://resolver.example/a b", String(repeating: "a", count: 2049)] {
            XCTAssertFalse(RegramNetworkPolicy.validEndpoint(endpoint), endpoint)
        }
    }

    func testNavigationRestoresMandatoryTabsAndIgnoresMalformedOrder() {
        var settings = RegramAccountSettings()
        settings["sidebarOrder"] = .strings(["settings", "calls", "calls", "unknown"])
        settings["sidebarHiddenTabs"] = .strings(["chats", "settings", "contacts"])
        var configuration = RegramNavigationConfiguration(settings: settings)
        XCTAssertEqual(configuration.order, [.settings, .calls, .contacts, .chats])
        XCTAssertEqual(configuration.visible(callsEnabled: false), [.settings, .chats])
        XCTAssertEqual(configuration.visible(callsEnabled: true), [.settings, .calls, .chats])
        configuration.order.swapAt(0, 3)
        configuration.apply(to: &settings)
        XCTAssertEqual(RegramNavigationConfiguration(settings: settings), configuration)
    }

    func testCatalogStableIdsAndUnicodeAliases() {
        let entries = RegramSettingsCatalog.entries
        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(Set(entries.map(\.stableId)).count, entries.count)
        XCTAssertTrue(entries.allSatisfy { $0.stableId >= 0x40000000 })
        XCTAssertFalse(entries.contains { ["tapMessageRowToOpenContextMenu", "allChatsTitleLengthOverride", "chatListFolderTabDisplayMode"].contains($0.key) })
        XCTAssertFalse(entries.contains { $0.key == "contentSettings" })
        for destination in ["networkPolicy/endpoint", "bottomBar/contacts", "groupProfile/location", "settings.stories/showRepostToStory"] {
            XCTAssertTrue(entries.contains(where: { $0.destination == destination }), destination)
        }
        XCTAssertFalse(entries.contains(where: { $0.category == .notifications }))
        XCTAssertTrue(entries.contains(where: { $0.page == "updates" }))
        XCTAssertTrue(RegramSettingsCatalog.results(query: "更新", language: "zh-Hans").contains(where: { $0.page == "updates" || $0.key == "appUpdate" }))
        XCTAssertTrue(RegramSettingsCatalog.results(query: "DoH", language: "en").contains(where: { $0.destination == "pro.network/networkPolicy" }))
        XCTAssertEqual(RegramSettingsCatalogEntry("networkPolicy", "endpoint", "NetworkPolicy.Endpoint").stableId, entries.first(where: { $0.destination == "networkPolicy/endpoint" })?.stableId)
        XCTAssertTrue(RegramSettingsSearchQuery("ＣＡＦＥ", language: "en").matches("café"))
        XCTAssertTrue(RegramSettingsSearchQuery("正则 过滤", language: "zh-Hans").matches("关键词 正则 过滤"))
        XCTAssertFalse(RegramSettingsSearchQuery("  ", language: "en").matches("anything"))
        XCTAssertFalse(RegramSettingsSearchQuery("DNS IPv6", language: "en").matches("DNS IPv4"))
    }

    func testRegistrationDateEstimatesStayMonotoneAndExplicitlyRanged() {
        XCTAssertNil(regramEstimateRegistrationDate(userId: 0))
        var previous: Int64 = 0
        for id: Int64 in [1, 2768409, 7679610, 400169472, 805158066, 1974255900, 8559682245, 9000000000] {
            let date = regramEstimateRegistrationDate(userId: id)!
            XCTAssertLessThan(date.from, date.to)
            let midpoint = date.from + (date.to - date.from) / 2
            XCTAssertGreaterThanOrEqual(midpoint, previous)
            XCTAssertLessThanOrEqual(midpoint, Int64(Date().timeIntervalSince1970))
            previous = midpoint
        }
    }
    func testTransferWindowExpiresRetriesAndSaturatesCounters() {
        let statistics = RegramTransferStatistics()
        statistics.recordReceived(byteCount: 300, now: 10)
        statistics.recordReceived(byteCount: 600, now: 11)
        XCTAssertEqual(statistics.snapshot(now: 12).receivedBytes, 900)
        XCTAssertEqual(statistics.snapshot(now: 12).bytesPerSecond, 300)
        XCTAssertEqual(statistics.snapshot(now: 13).bytesPerSecond, 200)
        XCTAssertEqual(statistics.snapshot(now: 14).bytesPerSecond, 0)
        statistics.recordReceived(byteCount: Int.max, now: 15)
        statistics.recordReceived(byteCount: 100, now: 15)
        XCTAssertEqual(statistics.snapshot(now: 15).receivedBytes, Int64.max)
        XCTAssertEqual(statistics.snapshot(now: .nan).bytesPerSecond, 0)
    }

}
