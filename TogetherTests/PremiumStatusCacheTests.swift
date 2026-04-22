import Testing
import Foundation
@testable import Together

@Suite
struct PremiumStatusCacheTests {
    private func makeDefaults() -> UserDefaults {
        // 独立 suite 避免污染真实 .standard
        let suite = UUID().uuidString
        return UserDefaults(suiteName: suite)!
    }

    @Test func emptyCacheReturnsNil() {
        let cache = PremiumStatusCache(
            defaults: makeDefaults(),
            dateProvider: FixedDateProvider(fixed: Date())
        )
        #expect(cache.load() == nil)
    }

    @Test func savedStatusRoundtrips() {
        let defaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 1000)
        let cache = PremiumStatusCache(
            defaults: defaults,
            dateProvider: FixedDateProvider(fixed: now)
        )
        let status = PremiumStatus.pro(source: .subscription, expiresAt: nil)
        cache.save(status)
        #expect(cache.load() == status)
    }

    @Test func expiredCacheReturnsNil() {
        let defaults = makeDefaults()
        let saveTime = Date(timeIntervalSince1970: 1000)
        let cacheAtSave = PremiumStatusCache(
            defaults: defaults,
            dateProvider: FixedDateProvider(fixed: saveTime)
        )
        cacheAtSave.save(.free)

        // 8 天后读取（超 7 天 TTL）
        let readTime = saveTime.addingTimeInterval(8 * 86400)
        let cacheAtRead = PremiumStatusCache(
            defaults: defaults,
            dateProvider: FixedDateProvider(fixed: readTime)
        )
        #expect(cacheAtRead.load() == nil)
    }

    @Test func cacheWithin7DaysStillValid() {
        let defaults = makeDefaults()
        let saveTime = Date(timeIntervalSince1970: 1000)
        let cacheAtSave = PremiumStatusCache(
            defaults: defaults,
            dateProvider: FixedDateProvider(fixed: saveTime)
        )
        cacheAtSave.save(.free)

        // 6 天后读取（仍在 7 天窗口内）
        let readTime = saveTime.addingTimeInterval(6 * 86400)
        let cacheAtRead = PremiumStatusCache(
            defaults: defaults,
            dateProvider: FixedDateProvider(fixed: readTime)
        )
        #expect(cacheAtRead.load() == .free)
    }

    @Test func clearRemovesStatus() {
        let defaults = makeDefaults()
        let cache = PremiumStatusCache(
            defaults: defaults,
            dateProvider: FixedDateProvider(fixed: Date())
        )
        cache.save(.free)
        cache.clear()
        #expect(cache.load() == nil)
    }
}
