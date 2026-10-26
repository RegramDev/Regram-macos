import Foundation

public struct RegramRegistrationDate: Equatable {
    public let from: Int64
    public let to: Int64
    public let validUntil: Int64

    public init(from: Int64, to: Int64, validUntil: Int64) {
        self.from = from
        self.to = to
        self.validUntil = validUntil
    }
}


private let rgRegDateAnchors: [(id: Int64, timestamp: Int64)] = [
    (2768409, 1383264000),
    (7679610, 1388448000),
    (11538514, 1391212800),
    (15835244, 1392854400),
    (23646077, 1393372800),
    (38015510, 1393632000),
    (44634663, 1399334400),
    (46145305, 1400112000),
    (54845238, 1411171200),
    (63263518, 1414368000),
    (101260938, 1425600000),
    (101323197, 1426204800),
    (103151531, 1432944000),
    (109393468, 1434326400),
    (112594714, 1438300800),
    (124872445, 1439769600),
    (125828524, 1442620800),
    (133909606, 1444176000),
    (143445125, 1448928000),
    (148670295, 1450828800),
    (171295414, 1457481600),
    (181783990, 1460246400),
    (222021233, 1465344000),
    (225034354, 1466208000),
    (278941742, 1473465600),
    (285253072, 1476748800),
    (294851037, 1479513600),
    (297621225, 1481846400),
    (328594461, 1482969600),
    (337808429, 1487635200),
    (341546272, 1487721600),
    (352940995, 1487894400),
    (369669043, 1490918400),
    (400169472, 1501459200),
    (805158066, 1563148800),
    (1974255900, 1633996800),
    (5022636255, 1638921600),
    (5045293264, 1642032000),
    (5047148663, 1645833600),
    (5106451106, 1646006400),
    (5153900870, 1647129600),
    (5244529493, 1648425600),
    (5308260177, 1650844800),
    (5340744210, 1655683200),
    (5434011049, 1656460800),
    (5442755368, 1658448000),
    (5515826405, 1662595200),
    (5520018289, 1667520000),
    (5738347976, 1670630400),
    (5802659303, 1674518400),
    (5869978651, 1676851200),
    (5994561143, 1682812800),
    (6326011828, 1688688000),
    (6401027363, 1698969600),
    (6536173556, 1703894400),
    (6559717847, 1705881600),
    (6854829938, 1706745600),
    (6872061796, 1707696000),
    (7002435197, 1712361600),
    (7078066115, 1718150400),
    (7224009547, 1719792000),
    (7243375923, 1721260800),
    (7273085448, 1723593600),
    (7342300216, 1725926400),
    (7450316621, 1727827200),
    (7591351660, 1736380800),
    (7817256746, 1738454400),
    (7834356221, 1749686400),
    (7912577935, 1750291200),
    (8179125032, 1752019200),
    (8200159552, 1757116800),
    (8384648263, 1760054400),
    (8480708838, 1762300800),
    (8559682245, 1762819200),
]

private let rgRegDateIdsPerDay: Double = 2_739_174.0

private let rgTelegramLaunchTimestamp: Int64 = 1_376_438_400

public func regramEstimateRegistrationDate(userId: Int64) -> RegramRegistrationDate? {
    guard userId > 0, !rgRegDateAnchors.isEmpty else {
        return nil
    }

    let first = rgRegDateAnchors[0]
    let last = rgRegDateAnchors[rgRegDateAnchors.count - 1]

    if userId <= first.id {
        return RegramRegistrationDate(from: rgTelegramLaunchTimestamp, to: first.timestamp, validUntil: 0)
    }

    if userId >= last.id {
        let days = Double(userId - last.id) / rgRegDateIdsPerDay
        let now = Int64(Date().timeIntervalSince1970)
        let estimate = min(last.timestamp + Int64(days * 86_400.0), now)
        let margin = max(Int64(30 * 86_400), Int64(days * 86_400.0 * 0.25))
        return RegramRegistrationDate(from: estimate - margin, to: estimate + margin, validUntil: 0)
    }

    var lowIndex = 0
    var highIndex = rgRegDateAnchors.count - 1
    while lowIndex + 1 < highIndex {
        let mid = (lowIndex + highIndex) / 2
        if rgRegDateAnchors[mid].id <= userId {
            lowIndex = mid
        } else {
            highIndex = mid
        }
    }

    let low = rgRegDateAnchors[lowIndex]
    let high = rgRegDateAnchors[highIndex]
    guard high.id > low.id else {
        return RegramRegistrationDate(from: low.timestamp, to: low.timestamp, validUntil: 0)
    }

    let ratio = Double(userId - low.id) / Double(high.id - low.id)
    let estimate = low.timestamp + Int64(ratio * Double(high.timestamp - low.timestamp))

    let margin = max(Int64(15 * 86_400), (high.timestamp - low.timestamp) / 2)
    return RegramRegistrationDate(from: estimate - margin, to: estimate + margin, validUntil: 0)
}
