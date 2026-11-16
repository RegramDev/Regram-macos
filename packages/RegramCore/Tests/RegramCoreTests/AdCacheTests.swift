import XCTest

@testable import RegramCore

@available(macOS 10.15, *)
final class AdCacheTests: XCTestCase {
    func testCostCountAndReplacementBounds() {
        var cache = RGAdBoundedCache<Int, String>(countLimit: 3, costLimit: 10)
        cache.insert("first", for: 1, cost: 6)
        cache.insert("second", for: 2, cost: 4)
        cache.insert("third", for: 3, cost: 5)
        XCTAssertNil(cache[1])
        XCTAssertEqual(cache.totalCost, 9)
        cache.insert("replace", for: 2, cost: 2)
        XCTAssertEqual(cache[2], "replace")
        XCTAssertEqual(cache.totalCost, 7)
        cache.insert("fourth", for: 4, cost: 1)
        cache.insert("fifth", for: 5, cost: 1)
        XCTAssertNil(cache[3])
        XCTAssertEqual(cache.count, 3)
        XCTAssertEqual(cache.totalCost, 4)
        cache.insert("oversized", for: 2, cost: 11)
        XCTAssertNil(cache[2])
        XCTAssertEqual(cache.totalCost, 2)
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.totalCost, 0)
    }

    func testLargeScoresCannotGrowPastByteBudget() {
        var cache = RGAdBoundedCache<String, Double>(countLimit: 2048, costLimit: 2 * 1024 * 1024)
        for index in 0..<2048 {
            let text = String(repeating: "长文本", count: 1000) + String(index)
            cache.insert(0.5, for: text, cost: text.utf8.count * 2 + 128)
        }
        XCTAssertLessThan(cache.count, 120)
        XCTAssertLessThanOrEqual(cache.totalCost, 2 * 1024 * 1024)
    }
}
