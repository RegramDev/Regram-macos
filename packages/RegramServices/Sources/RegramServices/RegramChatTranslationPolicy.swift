import RegramCore

public enum RegramChatTranslationPolicy {
    public enum Provider: String, CaseIterable {
        case telegram = "default"
        case system
        case google
        case googleCN
        case microsoft
        case yandex
        case transmart
        case llm
    }

    public static func provider(settings: RegramAccountSettings) -> Provider? {
        Provider(rawValue: settings["translationBackend"].string)
    }

    public static func usesTextRequests(settings: RegramAccountSettings, hasTelegramPremium: Bool) -> Bool {
        provider(settings: settings) != nil
    }

    public static func textRequestSettings(_ settings: RegramAccountSettings) -> RegramAccountSettings {
        settings
    }
}
