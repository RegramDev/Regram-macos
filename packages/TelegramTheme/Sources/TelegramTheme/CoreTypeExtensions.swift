import Cocoa
import TelegramCore
import Postbox
import ColorPalette
import TGUIKit

public extension Peer {
    var namePeerColor: PeerNameColor? {
        guard PeerNameColorProvider.isEnabled else { return nil }
        if let nameColor {
            switch nameColor {
            case .preset(let peerNameColor):
                return peerNameColor
            case .collectible:
                return nil
            }
        } else {
            return nil
        }
    }
}

public extension PeerNameColors {
    func get(_ color: PeerNameColor, dark: Bool = false) -> Colors {
        if dark, let colors = self.darkColors[color.rawValue] {
            return colors
        } else if let colors = self.colors[color.rawValue] {
            return colors
        } else {
            return PeerNameColors.defaultSingleColors[5]!
        }
    }
}

public extension Peer {
    func hasBannedRights(_ flags: TelegramChatBannedRightsFlags) -> Bool {
        if let peer = self as? TelegramChannel {
            if let _ = peer.hasBannedPermission(flags) {
                return true
            }
        } else if let peer = self as? TelegramGroup {
            return peer.hasBannedPermission(flags)
        }
        return false
    }
}
