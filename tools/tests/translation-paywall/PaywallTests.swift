import Foundation

__SETTINGS__

enum Flag: Hashable { case translationHidden }
class CachedChannelData { var flags: Set<Flag> = [] }
class CachedGroupData { var flags: Set<Flag> = [] }
class CachedUserData { var flags: Set<Flag> = [] }
enum Namespaces { enum Peer { static let SecretChat = 1 } }
struct PeerId { let namespace: Int }
struct TranslationState { var paywall = false }

func visibility(_ cachedData: Any?, secret: Bool = false) -> (hidden: Bool, paywall: Bool?) {
    let peerId = PeerId(namespace: secret ? Namespaces.Peer.SecretChat : 0)
    let translationState: TranslationState? = TranslationState()
    do {
        __VISIBILITY__
        return (isHidden, translationState?.paywall)
    }
}

var failures = 0
func check(_ passed: Bool, _ name: String) {
    print("\(passed ? "PASS" : "FAIL"): \(name)")
    if !passed { failures += 1 }
}

let now = Int32(Date().timeIntervalSince1970)
let eligible = TranslatePaywall(timestamp: now - 60, count: 3)
let dismissed = eligible.flush()
let expired = TranslatePaywall(timestamp: now - 1, count: dismissed.count + 2)

for cachedData: Any in [CachedChannelData(), CachedGroupData(), CachedUserData()] {
    let kind = String(describing: type(of: cachedData))
    let result = visibility(cachedData)
    check(!result.hidden, "\(kind): available translation stays visible")
    check(result.paywall == false, "\(kind): Regram does not show the old translation paywall")
    check(visibility(cachedData, secret: true).hidden, "\(kind): secret chat translation remains hidden")
}

let hiddenChannel = CachedChannelData()
hiddenChannel.flags.insert(.translationHidden)
check(visibility(hiddenChannel).hidden, "chat translation hidden flag remains respected")
check(visibility(nil).hidden, "missing chat data stays hidden")
check(dismissed.timestamp >= now + 7 * 24 * 60 * 60, "dismissal retains seven-day cooldown")
if failures > 0 { exit(1) }
