import Cocoa
import TelegramTheme
import SwiftSignalKit
import TGUIKit
import RegramCore
import RegramServices
import TelegramCore
import Localization
import ColorPalette
import ThemeSettings
import Postbox

func applyRegramUILocalization(_ settings: LocalizationSettings) {
    func component(_ value: LocalizationComponent) -> LocalizationComponent {
        let strings = RegramLanguagePack.nativeMacOSStrings(languageCode: value.languageCode)
        guard !strings.isEmpty else { return value }
        let entries = value.localization.entries.filter { entry in
            switch entry {
            case let .string(key, _), let .pluralizedString(key, _, _, _, _, _, _): return strings[key] == nil
            }
        } + strings.sorted(by: { $0.key < $1.key }).map { LocalizationEntry.string(key: $0.key, value: $0.value) }
        return LocalizationComponent(languageCode: value.languageCode, localizedName: value.localizedName, localization: TelegramCore.Localization(version: value.localization.version, entries: entries), customPluralizationCode: value.customPluralizationCode)
    }
    applyUILocalization(LocalizationSettings(primaryComponent: component(settings.primaryComponent), secondaryComponent: settings.secondaryComponent.map(component)))
}

func regramRepairedThemePalette(_ palette: ColorPalette) -> ColorPalette {
    guard palette.name == "Regram Graphite", palette.copyright == "Regram", palette.isDark, palette.parent == .dark,
          palette.background == NSColor(0x242830), palette.listBackground == palette.background else { return palette }
    return ColorPalette(isNative: palette.isNative, isDark: palette.isDark,
        tinted: palette.tinted,
        name: palette.name,
        parent: palette.parent,
        wallpaper: palette.wallpaper,
        copyright: palette.copyright,
        accentList: palette.accentList,
        basicAccent: palette.basicAccent,
        background: palette.background,
        text: palette.text,
        grayText: palette.grayText,
        link: palette.link,
        accent: palette.accent,
        redUI: palette.redUI,
        greenUI: palette.greenUI,
        blackTransparent: palette.blackTransparent,
        grayTransparent: palette.grayTransparent,
        grayUI: palette.grayUI,
        darkGrayText: palette.darkGrayText,
        accentSelect: palette.accentSelect,
        selectText: palette.selectText,
        border: palette.border,
        grayBackground: palette.grayBackground,
        grayForeground: palette.grayForeground,
        grayIcon: palette.grayIcon,
        accentIcon: palette.accentIcon,
        badgeMuted: palette.badgeMuted,
        badge: palette.badge,
        indicatorColor: palette.indicatorColor,
        selectMessage: palette.selectMessage,
        monospacedPre: palette.monospacedPre,
        monospacedCode: palette.monospacedCode,
        monospacedPreBubble_incoming: palette.monospacedPreBubble_incoming,
        monospacedPreBubble_outgoing: palette.monospacedPreBubble_outgoing,
        monospacedCodeBubble_incoming: palette.monospacedCodeBubble_incoming,
        monospacedCodeBubble_outgoing: palette.monospacedCodeBubble_outgoing,
        selectTextBubble_incoming: palette.selectTextBubble_incoming,
        selectTextBubble_outgoing: palette.selectTextBubble_outgoing,
        bubbleBackground_incoming: palette.bubbleBackground_incoming,
        bubbleBackground_outgoing: palette.bubbleBackground_outgoing,
        bubbleBorder_incoming: palette.bubbleBorder_incoming,
        bubbleBorder_outgoing: palette.bubbleBorder_outgoing,
        grayTextBubble_incoming: palette.grayTextBubble_incoming,
        grayTextBubble_outgoing: palette.grayTextBubble_outgoing,
        grayIconBubble_incoming: palette.grayIconBubble_incoming,
        grayIconBubble_outgoing: palette.grayIconBubble_outgoing,
        accentIconBubble_incoming: palette.accentIconBubble_incoming,
        accentIconBubble_outgoing: palette.accentIconBubble_outgoing,
        linkBubble_incoming: palette.linkBubble_incoming,
        linkBubble_outgoing: palette.linkBubble_outgoing,
        textBubble_incoming: palette.textBubble_incoming,
        textBubble_outgoing: palette.textBubble_outgoing,
        selectMessageBubble: palette.selectMessageBubble,
        fileActivityBackground: palette.fileActivityBackground,
        fileActivityForeground: palette.fileActivityForeground,
        fileActivityBackgroundBubble_incoming: palette.fileActivityBackgroundBubble_incoming,
        fileActivityBackgroundBubble_outgoing: palette.fileActivityBackgroundBubble_outgoing,
        fileActivityForegroundBubble_incoming: palette.fileActivityForegroundBubble_incoming,
        fileActivityForegroundBubble_outgoing: palette.fileActivityForegroundBubble_outgoing,
        waveformBackground: palette.waveformBackground,
        waveformForeground: palette.waveformForeground,
        waveformBackgroundBubble_incoming: palette.waveformBackgroundBubble_incoming,
        waveformBackgroundBubble_outgoing: palette.waveformBackgroundBubble_outgoing,
        waveformForegroundBubble_incoming: palette.waveformForegroundBubble_incoming,
        waveformForegroundBubble_outgoing: palette.waveformForegroundBubble_outgoing,
        webPreviewActivity: palette.webPreviewActivity,
        webPreviewActivityBubble_incoming: palette.webPreviewActivityBubble_incoming,
        webPreviewActivityBubble_outgoing: palette.webPreviewActivityBubble_outgoing,
        redBubble_incoming: palette.redBubble_incoming,
        redBubble_outgoing: palette.redBubble_outgoing,
        greenBubble_incoming: palette.greenBubble_incoming,
        greenBubble_outgoing: palette.greenBubble_outgoing,
        chatReplyTitle: palette.chatReplyTitle,
        chatReplyTextEnabled: palette.chatReplyTextEnabled,
        chatReplyTextDisabled: palette.chatReplyTextDisabled,
        chatReplyTitleBubble_incoming: palette.chatReplyTitleBubble_incoming,
        chatReplyTitleBubble_outgoing: palette.chatReplyTitleBubble_outgoing,
        chatReplyTextEnabledBubble_incoming: palette.chatReplyTextEnabledBubble_incoming,
        chatReplyTextEnabledBubble_outgoing: palette.chatReplyTextEnabledBubble_outgoing,
        chatReplyTextDisabledBubble_incoming: palette.chatReplyTextDisabledBubble_incoming,
        chatReplyTextDisabledBubble_outgoing: palette.chatReplyTextDisabledBubble_outgoing,
        groupPeerNameRed: palette.groupPeerNameRed,
        groupPeerNameOrange: palette.groupPeerNameOrange,
        groupPeerNameViolet: palette.groupPeerNameViolet,
        groupPeerNameGreen: palette.groupPeerNameGreen,
        groupPeerNameCyan: palette.groupPeerNameCyan,
        groupPeerNameLightBlue: palette.groupPeerNameLightBlue,
        groupPeerNameBlue: palette.groupPeerNameBlue,
        peerAvatarRedTop: palette.peerAvatarRedTop,
        peerAvatarRedBottom: palette.peerAvatarRedBottom,
        peerAvatarOrangeTop: palette.peerAvatarOrangeTop,
        peerAvatarOrangeBottom: palette.peerAvatarOrangeBottom,
        peerAvatarVioletTop: palette.peerAvatarVioletTop,
        peerAvatarVioletBottom: palette.peerAvatarVioletBottom,
        peerAvatarGreenTop: palette.peerAvatarGreenTop,
        peerAvatarGreenBottom: palette.peerAvatarGreenBottom,
        peerAvatarCyanTop: palette.peerAvatarCyanTop,
        peerAvatarCyanBottom: palette.peerAvatarCyanBottom,
        peerAvatarBlueTop: palette.peerAvatarBlueTop,
        peerAvatarBlueBottom: palette.peerAvatarBlueBottom,
        peerAvatarPinkTop: palette.peerAvatarPinkTop,
        peerAvatarPinkBottom: palette.peerAvatarPinkBottom,
        bubbleBackgroundHighlight_incoming: palette.bubbleBackgroundHighlight_incoming,
        bubbleBackgroundHighlight_outgoing: palette.bubbleBackgroundHighlight_outgoing,
        chatDateActive: palette.chatDateActive,
        chatDateText: palette.chatDateText,
        revealAction_neutral1_background: palette.revealAction_neutral1_background,
        revealAction_neutral1_foreground: palette.revealAction_neutral1_foreground,
        revealAction_neutral2_background: palette.revealAction_neutral2_background,
        revealAction_neutral2_foreground: palette.revealAction_neutral2_foreground,
        revealAction_destructive_background: palette.revealAction_destructive_background,
        revealAction_destructive_foreground: palette.revealAction_destructive_foreground,
        revealAction_constructive_background: palette.revealAction_constructive_background,
        revealAction_constructive_foreground: palette.revealAction_constructive_foreground,
        revealAction_accent_background: palette.revealAction_accent_background,
        revealAction_accent_foreground: palette.revealAction_accent_foreground,
        revealAction_warning_background: palette.revealAction_warning_background,
        revealAction_warning_foreground: palette.revealAction_warning_foreground,
        revealAction_inactive_background: palette.revealAction_inactive_background,
        revealAction_inactive_foreground: palette.revealAction_inactive_foreground,
        chatBackground: palette.chatBackground,
        listBackground: NSColor(0x1e2127),
        listGrayText: palette.listGrayText,
        grayHighlight: palette.grayHighlight,
        focusAnimationColor: palette.focusAnimationColor,
        premium: palette.premium,
        vibrant: palette.vibrant)
}

func bindRegramThemeRepairs(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Disposable {
    (themeSettingsView(accountManager: accountManager) |> mapToSignal { settings -> Signal<Void, NoError> in
        guard regramRepairedThemePalette(settings.palette) !== settings.palette else { return .complete() }
        return updateThemeInteractivetly(accountManager: accountManager, f: { settings in
            let palette = regramRepairedThemePalette(settings.palette)
            return palette === settings.palette ? settings : settings.withUpdatedPalette(palette)
        })
    }).start()
}
