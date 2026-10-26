import Foundation

private func order(_ timestamp: Int32, peer: Int64 = 1, id: Int32 = 1) -> RegramSearchMessageOrder {
    RegramSearchMessageOrder(timestamp: timestamp, peerId: peer, namespace: 0, messageId: id)
}

@main enum RegramMessageSearchPolicyTests {
    static func main() {
        let fresh = (1...8).map { RegramGroupSearchStatus(peerId: Int64($0)) }
        precondition(RegramMessageSearchPolicy.nextGroups(fresh, orders: [], visibleLimit: 50, selectedGroup: nil) == [1, 2, 3])
        var statuses = fresh
        statuses[0].loading = true
        statuses[1].loading = true
        precondition(RegramMessageSearchPolicy.nextGroups(statuses, orders: [], visibleLimit: 50, selectedGroup: nil) == [3])
        precondition(RegramMessageSearchPolicy.nextGroups(statuses, orders: [], visibleLimit: 50, selectedGroup: 6) == [6])
        statuses[2].loading = true
        precondition(RegramMessageSearchPolicy.nextGroups(statuses, orders: [], visibleLimit: 50, selectedGroup: 6).isEmpty)
        let visible = (90...139).map { order(Int32($0)) }
        var hot = RegramGroupSearchStatus(peerId: 1)
        hot.loaded = true
        hot.oldest = order(100)
        var quiet = RegramGroupSearchStatus(peerId: 2)
        quiet.loaded = true
        quiet.oldest = order(70)
        precondition(RegramMessageSearchPolicy.nextGroups([hot, quiet], orders: visible, visibleLimit: 50, selectedGroup: nil) == [1])
        hot.failed = true
        precondition(RegramMessageSearchPolicy.nextGroups([hot, quiet], orders: [], visibleLimit: 50, selectedGroup: nil) == [2])
        hot.failed = false
        hot.oldest = order(80)
        precondition(RegramMessageSearchPolicy.nextGroups([hot, quiet], orders: visible, visibleLimit: 50, selectedGroup: nil).isEmpty)
        precondition(RegramMessageSearchPolicy.nextGroups([hot, quiet], orders: visible, visibleLimit: 100, selectedGroup: nil) == [1, 2])
        precondition(Set([order(10), order(10, peer: 2), order(10, id: 2)]).count == 3)
        precondition(RegramMessageSearchPolicy.preview("public secret", spoilers: [7..<13], reveal: false) == "public ▪▪▪▪▪▪")
        precondition(RegramMessageSearchPolicy.preview("public secret", spoilers: [7..<13], reveal: true) == "public secret")
        precondition(RegramMessageSearchPolicy.preview("A😀秘密", spoilers: [1..<4], reveal: false) == "A▪▪▪密")
        precondition(RegramMessageSearchPolicy.preview("abc", spoilers: [-3..<1, 9..<10], reveal: false) == "▪bc")
        precondition(RegramMessageSearchPolicy.preview(String(repeating: "a", count: 1000), spoilers: [590..<1000], reveal: false).count == 600)

        var seed: UInt64 = 283363
        func random(_ upper: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(upper))
        }
        for trial in 0..<30 {
            let server: [[RegramSearchMessageOrder]] = (1...18).map { group in
                (0..<random(group == 1 ? 1500 : 300)).map { message in
                    order(Int32(random(100_000)), peer: Int64(group), id: Int32(message))
                }.sorted(by: >)
            }
            var statuses = (1...18).map { RegramGroupSearchStatus(peerId: Int64($0)) }
            var loaded: [Int64: [RegramSearchMessageOrder]] = [:]
            func locallyVisible(_ message: RegramSearchMessageOrder) -> Bool {
                trial % 2 == 0 || message.messageId % 4 == 0
            }
            for (limit, selected) in [(50, Optional<Int64>.none), (100, nil), (250, nil), (50, 7), (150, 7)] {
                var requests = 0
                while true {
                    let known = loaded.filter { selected == nil || $0.key == selected }.values.flatMap { $0 }.filter(locallyVisible)
                    let next = RegramMessageSearchPolicy.nextGroups(statuses, orders: known, visibleLimit: limit, selectedGroup: selected)
                    if next.isEmpty { break }
                    for id in next {
                        let index = Int(id) - 1
                        let count = min(server[index].count, (loaded[id]?.count ?? 0) + Int(RegramMessageSearchPolicy.pageSize))
                        loaded[id] = Array(server[index].prefix(count))
                        statuses[index].loaded = true
                        statuses[index].hasMore = count < server[index].count
                        statuses[index].oldest = loaded[id]?.last
                        requests += 1
                    }
                    precondition(requests < 1000)
                }
                let expected = server.enumerated().filter { selected == nil || Int64($0.offset + 1) == selected }.flatMap(\.element).filter(locallyVisible).sorted(by: >).prefix(limit)
                let actual = loaded.filter { selected == nil || $0.key == selected }.values.flatMap { $0 }.filter(locallyVisible).sorted(by: >).prefix(limit)
                precondition(Array(actual) == Array(expected))
            }
        }
        print("Regram message search: pagination, global ordering, group selection, local filters, concurrency, failure retry and spoiler previews passed.")
    }
}
