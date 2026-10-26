import Foundation

public enum RGVideoQualityPreference: String, CaseIterable {
    case automatic
    case highest
    case lowest

    public func selectedQuality(available: [Int]) -> Int? {
        let available = Set(available.filter { $0 > 0 })
        guard available.count > 1 else { return nil }
        switch self {
        case .automatic: return nil
        case .highest: return available.max()
        case .lowest: return available.min()
        }
    }

    public static let settingsChanged = Notification.Name("Regram.DefaultVideoQualityChanged")
}
