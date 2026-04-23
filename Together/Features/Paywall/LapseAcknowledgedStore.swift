import Foundation

/// Pro→Free lapse sheet 的去重持久化。按 dedupKey 存 UserDefaults `[String]`，
/// 内存里用 `Set<String>` 加速 contains。spec § 2.5。
@MainActor
final class LapseAcknowledgedStore {
    private let defaults: UserDefaults
    private let key: String
    private(set) var keys: Set<String>

    init(defaults: UserDefaults = .standard,
         key: String = "com.pigdog.Together.premium.lapseAcknowledgedKeys") {
        self.defaults = defaults
        self.key = key
        self.keys = Set(defaults.stringArray(forKey: key) ?? [])
    }

    func contains(_ dedupKey: String) -> Bool { keys.contains(dedupKey) }

    func insert(_ dedupKey: String) {
        guard keys.insert(dedupKey).inserted else { return }
        defaults.set(Array(keys), forKey: key)
    }

    #if DEBUG
    /// DEBUG only：清空已确认的 lapse 去重列表，方便反复测试。
    func reset() {
        keys.removeAll()
        defaults.removeObject(forKey: key)
    }
    #endif
}
