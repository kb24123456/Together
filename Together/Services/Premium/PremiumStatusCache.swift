import Foundation

/// `PremiumStatus` 的 UserDefaults 包装。
///
/// 带 7 天 TTL，平衡"离线宽松回退"和"订阅状态变更尽快生效"。
/// 任何一次成功的查询都应 save 结果；查询全部失败时 load 作为兜底。
final class PremiumStatusCache {
    private static let statusKey = "premium.cachedStatus.v1"
    private static let timestampKey = "premium.cachedStatusTimestamp.v1"
    private static let ttl: TimeInterval = 7 * 24 * 3600

    private let defaults: UserDefaults
    private let dateProvider: DateProvider

    init(defaults: UserDefaults = .standard, dateProvider: DateProvider) {
        self.defaults = defaults
        self.dateProvider = dateProvider
    }

    /// 读取缓存。若过期或不存在，返回 nil。
    func load() -> PremiumStatus? {
        guard
            let savedAt = defaults.object(forKey: Self.timestampKey) as? Date,
            dateProvider.now().timeIntervalSince(savedAt) <= Self.ttl,
            let data = defaults.data(forKey: Self.statusKey)
        else {
            return nil
        }
        return try? JSONDecoder().decode(PremiumStatus.self, from: data)
    }

    /// 持久化 status + 当前时间戳。
    func save(_ status: PremiumStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        defaults.set(data, forKey: Self.statusKey)
        defaults.set(dateProvider.now(), forKey: Self.timestampKey)
    }

    /// 登出时调用，清理缓存。
    func clear() {
        defaults.removeObject(forKey: Self.statusKey)
        defaults.removeObject(forKey: Self.timestampKey)
    }
}
