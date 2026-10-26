public enum RegramTransferPolicy {
    public static func downloadPartSize(defaultValue: Int64, fileSize: Int64?, enabled: Bool, adaptive: Bool) -> Int64 {
        guard enabled, !adaptive, fileSize.map({ $0 > 1024 * 1024 }) ?? true else { return defaultValue }
        return max(defaultValue, 512 * 1024)
    }

    public static func pendingParts(defaultValue: Int, enabled: Bool, adaptive: Bool) -> Int {
        enabled && !adaptive ? max(defaultValue, 8) : defaultValue
    }
}
