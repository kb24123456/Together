# Phase 2 Premium Infrastructure 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Together 搭建完整的会员门禁基础设施——客户端 `PremiumGate` + Supabase `premium_grants` 表 + RevenueCat SDK 接入 + 4 个业务模块的门禁改造。

**Architecture:** RevenueCat SDK 负责订阅验证，Supabase 表存白名单，客户端用 `@Observable PremiumGate` 合并两路信号（源无关的 14 天 Grace Period 逻辑）。ViewModel 通过 `UpsellTrigger` 观察式属性向 View 传信号，不走 Error 通道。

**Tech Stack:** SwiftUI + SwiftData + CloudKit + Supabase + RevenueCat 5.x + Swift Testing（`@Test` / `#expect`）。

---

## 源 Spec 与上游文档

- **本 plan 对应 spec**: `docs/superpowers/specs/2026-04-22-premium-infrastructure-design.md` (Final)
- **产品 spec**: `docs/superpowers/specs/2026-04-22-premium-tier-split-design.md` (Final)
- **Roadmap**: `docs/superpowers/plans/2026-04-22-premium-rollout-roadmap.md` Track A3

## 文件结构

### 新建文件（源码）

```
Together/Services/Premium/
├── PremiumStatus.swift            — enum + PremiumSource + Codable
├── UpsellTrigger.swift            — ViewModel→View 升级信号
├── PremiumGateError.swift         — 仅 .quotaExceeded
├── DateProvider.swift             — 时间注入抽象（for 测试）
├── PremiumStatusCache.swift       — UserDefaults + 7 天 TTL
├── RCClientProtocol.swift         — RevenueCat 访问抽象
├── GrantsLoader.swift             — Supabase premium_grants 查询（含 Protocol）
├── RevenueCatConfig.swift         — public SDK key + entitlement id 常量
├── RevenueCatClient.swift         — RCClientProtocol 的真实实现
└── PremiumGate.swift              — 核心 @Observable 类
```

### 新建文件（后端）

```
supabase/
├── config.toml
└── migrations/
    └── <timestamp>_premium_grants.sql
```

### 新建测试（扁平放置，跟随项目现有惯例）

```
TogetherTests/
├── PremiumStatusTests.swift
├── PremiumStatusCacheTests.swift
├── PremiumGateMergeTests.swift
├── PremiumGateLifecycleTests.swift
├── ImportantDatesViewModelQuotaTests.swift
├── ProjectsViewModelQuotaTests.swift
├── CompletedHistoryViewModelSinceTests.swift
└── SyncEngineCoordinatorGuardTests.swift
```

### 修改文件

| 文件 | 改动 |
|---|---|
| `Together/App/AppContainer.swift` | 构造并持有 `PremiumGate` |
| `Together/App/AppContext.swift` | 生命周期挂钩：`configurePremiumGate()` / `teardownPremiumGate()` |
| `Together/Sync/Engine/SyncEngineCoordinator.swift:60` | 在 `startSoloSync()` 开头加 `isPremium` guard |
| `Together/Services/Items/ItemRepository.swift` | `fetchCompletedItems` 加 `since:` 参数到 protocol |
| `Together/Services/Items/LocalItemRepository.swift` | 实现 `since:` |
| `Together/Services/Items/MockItemRepository.swift` | 实现 `since:` |
| `Together/Sync/SupabaseSyncService.swift` | 实现 `since:`（如走 Supabase 路径） |
| `Together/Features/Profile/CompletedHistoryViewModel.swift` | 注入 `PremiumGate` + 传 `since:` |
| `Together/Features/Anniversaries/ImportantDatesViewModel.swift` | `save()` 拆为 `createNew` / `updateExisting` + 门禁 |
| `Together/Features/Projects/ProjectsViewModel.swift` | 拆分 + 门禁 |
| `Together/Features/Profile/ProfileDebugSection.swift` | DEBUG 会员状态 override 控件 |
| `Together.xcodeproj` | 添加 `purchases-ios` SPM 依赖 |

---

## 实施顺序（按风险从低到高）

1. **Tasks 1–4**：纯数据类型（`PremiumStatus` / `UpsellTrigger` / `PremiumGateError` / `DateProvider`）
2. **Task 5**：`PremiumStatusCache`（依赖 `DateProvider`）
3. **Task 6**：`RCClientProtocol` + `GrantsLoader` 协议定义（无实现）
4. **Tasks 7–8**：`PremiumGate` 合并逻辑 + 生命周期
5. **Task 9**：Supabase migration（后端独立可推进）
6. **Tasks 10–12**：RevenueCat SPM 依赖 + `RevenueCatConfig` + `RevenueCatClient` 实现
7. **Task 13**：`GrantsLoader` 实现
8. **Tasks 14–15**：`AppContainer` / `AppContext` 接线
9. **Task 16**：`SyncEngineCoordinator` guard
10. **Tasks 17–18**：`ItemRepository.since:` 参数 + `CompletedHistoryViewModel` 接线
11. **Tasks 19–20**：`ImportantDatesViewModel` / `ProjectsViewModel` 拆分 + 门禁
12. **Task 21**：`ProfileDebugSection` override 控件
13. **Task 22**：端到端 smoke test 清单

---

## Task 1：`PremiumStatus` 枚举

**目的**：定义会员状态数据模型 + Codable 支持（用于缓存序列化）。

**Files:**
- Create: `Together/Services/Premium/PremiumStatus.swift`
- Test: `TogetherTests/PremiumStatusTests.swift`

### Step 1: 写失败测试

文件：`TogetherTests/PremiumStatusTests.swift`

```swift
import Testing
import Foundation
@testable import Together

@Suite
struct PremiumStatusTests {
    @Test func freeIsNotPremium() {
        #expect(PremiumStatus.free.isPremium == false)
        #expect(PremiumStatus.free.allowsFullLogbook == false)
    }

    @Test func unknownIsNotPremium() {
        #expect(PremiumStatus.unknown.isPremium == false)
        #expect(PremiumStatus.unknown.allowsFullLogbook == false)
    }

    @Test func proIsPremium() {
        let status = PremiumStatus.pro(source: .subscription, expiresAt: nil)
        #expect(status.isPremium)
        #expect(status.allowsFullLogbook)
    }

    @Test func gracePeriodAllowsFullLogbook() {
        let status = PremiumStatus.gracePeriod(
            originalExpiry: Date(timeIntervalSince1970: 1000),
            logbookFullUntil: Date(timeIntervalSince1970: 1000 + 14 * 86400)
        )
        #expect(status.isPremium)
        #expect(status.allowsFullLogbook)
    }

    @Test func codableRoundtripForFree() throws {
        let original = PremiumStatus.free
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PremiumStatus.self, from: data)
        #expect(decoded == original)
    }

    @Test func codableRoundtripForProWithExpiry() throws {
        let expiry = Date(timeIntervalSince1970: 2000)
        let original = PremiumStatus.pro(source: .grant, expiresAt: expiry)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PremiumStatus.self, from: data)
        #expect(decoded == original)
    }

    @Test func codableRoundtripForGrace() throws {
        let original = PremiumStatus.gracePeriod(
            originalExpiry: Date(timeIntervalSince1970: 1000),
            logbookFullUntil: Date(timeIntervalSince1970: 1000 + 14 * 86400)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PremiumStatus.self, from: data)
        #expect(decoded == original)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/PremiumStatusTests 2>&1 | tail -20
```

Expected: 编译失败（`PremiumStatus` 未定义）

### Step 3: 写最小实现

文件：`Together/Services/Premium/PremiumStatus.swift`

```swift
import Foundation

/// 会员状态。由 `PremiumGate` 合并 RC 订阅与 Supabase white-list grants 得出。
///
/// - `.unknown` 尚未 bootstrap（启动中）
/// - `.free` 无任何会员权益
/// - `.pro(source:, expiresAt:)` 活跃会员；`expiresAt == nil` 即永久
/// - `.gracePeriod(...)` 订阅或 grant 最近 14 天内过期；Logbook 仍展示全历史
enum PremiumStatus: Equatable, Codable {
    case unknown
    case free
    case pro(source: PremiumSource, expiresAt: Date?)
    case gracePeriod(originalExpiry: Date, logbookFullUntil: Date)

    enum PremiumSource: String, Codable {
        case subscription
        case grant
    }

    var isPremium: Bool {
        switch self {
        case .pro, .gracePeriod: return true
        case .unknown, .free: return false
        }
    }

    /// Logbook 是否允许展示全历史。Pro 和 gracePeriod 均允许。
    var allowsFullLogbook: Bool { isPremium }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/PremiumStatusTests 2>&1 | tail -20
```

Expected: 所有 7 个 test 通过

- [ ] **Step 5: Commit**

```bash
git add Together/Services/Premium/PremiumStatus.swift TogetherTests/PremiumStatusTests.swift
git commit -m "feat(premium): add PremiumStatus enum with Codable

Core data model for the premium gate. Supports four states:
unknown (pre-bootstrap), free, pro (with source + optional expiry),
and gracePeriod (with original expiry + logbookFullUntil cutoff).

Codable-serializable for cache persistence."
```

---

## Task 2：`UpsellTrigger` 枚举

**目的**：定义 ViewModel→View 的升级信号模型，每个配额门禁场景对应一个 case。

**Files:**
- Create: `Together/Services/Premium/UpsellTrigger.swift`

### Step 1: 写失败测试

文件：`TogetherTests/PremiumStatusTests.swift`（追加到同一文件末尾）

```swift
@Suite
struct UpsellTriggerTests {
    @Test func allCasesHaveUniqueIDs() {
        let ids: Set<String> = [
            UpsellTrigger.anniversaryQuota.id,
            UpsellTrigger.projectQuota.id,
            UpsellTrigger.logbookHistory.id,
            UpsellTrigger.crossDeviceSync.id
        ]
        #expect(ids.count == 4)
    }

    @Test func identifiableIsStable() {
        // Same case should produce same id twice
        #expect(UpsellTrigger.anniversaryQuota.id == UpsellTrigger.anniversaryQuota.id)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/UpsellTriggerTests 2>&1 | tail -10
```

Expected: `UpsellTrigger` 未定义

### Step 3: 实现

文件：`Together/Services/Premium/UpsellTrigger.swift`

```swift
import Foundation

/// ViewModel → View 的"触发付费墙"信号。每个值对应产品 spec § 3 的一个触发场景。
///
/// 观察式消费模式：ViewModel 暴露 `pendingUpsellTrigger: UpsellTrigger?`，
/// View 通过 `.sheet(item:)` 展示对应 Phase 3 付费墙视图。
enum UpsellTrigger: Identifiable, Equatable {
    case anniversaryQuota     // 新建第 6 个纪念日
    case projectQuota         // 新建第 4 个项目
    case logbookHistory       // Logbook 滚到 31 天前
    case crossDeviceSync      // 新设备首次打开且本机无数据

    var id: String {
        switch self {
        case .anniversaryQuota: return "anniversary_quota"
        case .projectQuota: return "project_quota"
        case .logbookHistory: return "logbook_history"
        case .crossDeviceSync: return "cross_device_sync"
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/UpsellTriggerTests 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
git add Together/Services/Premium/UpsellTrigger.swift TogetherTests/PremiumStatusTests.swift
git commit -m "feat(premium): add UpsellTrigger enum for ViewModel→View upsell signals"
```

---

## Task 3：`PremiumGateError` + `DateProvider`

**目的**：添加配额超限错误类型 + 时间抽象（用于测试 Grace Period）。

**Files:**
- Create: `Together/Services/Premium/PremiumGateError.swift`
- Create: `Together/Services/Premium/DateProvider.swift`

### Step 1: 写失败测试

文件：`TogetherTests/PremiumStatusTests.swift`（追加）

```swift
@Suite
struct PremiumGateErrorTests {
    @Test func quotaExceededIsEquatable() {
        let a = PremiumGateError.quotaExceeded(limit: 5, feature: .anniversary)
        let b = PremiumGateError.quotaExceeded(limit: 5, feature: .anniversary)
        let c = PremiumGateError.quotaExceeded(limit: 3, feature: .project)
        #expect(a == b)
        #expect(a != c)
    }
}

@Suite
struct DateProviderTests {
    @Test func systemProviderReturnsCurrentTime() {
        let provider = SystemDateProvider()
        let before = Date()
        let mid = provider.now()
        let after = Date()
        #expect(mid >= before && mid <= after)
    }

    @Test func fixedProviderReturnsFixedTime() {
        let fixed = Date(timeIntervalSince1970: 1000)
        let provider = FixedDateProvider(fixed: fixed)
        #expect(provider.now() == fixed)
        #expect(provider.now() == fixed)  // 多次调用仍相同
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/PremiumGateErrorTests -only-testing:TogetherTests/DateProviderTests 2>&1 | tail -10
```

### Step 3: 实现

文件：`Together/Services/Premium/PremiumGateError.swift`

```swift
import Foundation

enum PremiumGateError: Error, Equatable {
    case quotaExceeded(limit: Int, feature: GatedFeature)
}

enum GatedFeature: String, Equatable {
    case anniversary
    case project
    case logbookHistory
}
```

文件：`Together/Services/Premium/DateProvider.swift`

```swift
import Foundation

/// 时间获取抽象。生产代码用 `SystemDateProvider`，测试用 `FixedDateProvider`。
protocol DateProvider: Sendable {
    func now() -> Date
}

struct SystemDateProvider: DateProvider {
    func now() -> Date { Date() }
}

/// 测试用：返回一个固定时间。
struct FixedDateProvider: DateProvider {
    let fixed: Date
    func now() -> Date { fixed }
}
```

- [ ] **Step 4: 运行测试**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/PremiumGateErrorTests -only-testing:TogetherTests/DateProviderTests 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
git add Together/Services/Premium/PremiumGateError.swift Together/Services/Premium/DateProvider.swift TogetherTests/PremiumStatusTests.swift
git commit -m "feat(premium): add PremiumGateError and DateProvider abstraction"
```

---

## Task 4：`PremiumStatusCache`（UserDefaults + 7 天 TTL）

**目的**：持久化 `PremiumStatus`，支持离线模式下的宽松回退。

**Files:**
- Create: `Together/Services/Premium/PremiumStatusCache.swift`
- Create: `TogetherTests/PremiumStatusCacheTests.swift`

### Step 1: 写失败测试

文件：`TogetherTests/PremiumStatusCacheTests.swift`

```swift
import Testing
import Foundation
@testable import Together

@Suite
struct PremiumStatusCacheTests {
    private func makeDefaults() -> UserDefaults {
        // 使用独立 suite 避免污染真实 .standard
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
```

- [ ] **Step 2: 运行确认失败**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/PremiumStatusCacheTests 2>&1 | tail -10
```

### Step 3: 实现

文件：`Together/Services/Premium/PremiumStatusCache.swift`

```swift
import Foundation

/// `PremiumStatus` 的 UserDefaults 包装。带 7 天 TTL，保护离线体验同时避免订阅变更长期不生效。
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
```

- [ ] **Step 4: 运行测试**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/PremiumStatusCacheTests 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
git add Together/Services/Premium/PremiumStatusCache.swift TogetherTests/PremiumStatusCacheTests.swift
git commit -m "feat(premium): add PremiumStatusCache with 7-day TTL

UserDefaults-backed cache for PremiumStatus. Enables lenient offline
fallback (if both RC and Supabase queries fail but cache is fresh,
return cached status instead of .free)."
```

---

## Task 5：`RCClientProtocol` + `GrantsLoaderProtocol`（仅协议定义）

**目的**：定义 PremiumGate 的两个外部依赖接口，为后续 mock 和测试打基础。

**Files:**
- Create: `Together/Services/Premium/RCClientProtocol.swift`
- Create: `Together/Services/Premium/GrantsLoader.swift`

### Step 1: 定义两个协议 + 数据结构（纯定义，无测试）

文件：`Together/Services/Premium/RCClientProtocol.swift`

```swift
import Foundation

/// `PremiumGate` 对 RevenueCat 的访问抽象。生产实现由 `RevenueCatClient` 提供，
/// 测试实现由 stub 提供。
protocol RCClientProtocol: Sendable {
    /// 查询当前 appUserID 的 entitlement 状态。
    /// 失败时抛错（网络问题、未 configure 等）。
    func fetchCustomerInfo() async throws -> RCEntitlementSnapshot

    /// 切换到新的 appUserID（登录新账号）。
    func logIn(appUserID: String) async throws

    /// 清除当前用户关联（登出）。
    func logOut() async throws

    /// 是否已完成 configure。
    var isConfigured: Bool { get }

    /// 首次 configure（仅应在未 configured 时调用）。
    func configure(publicSDKKey: String, appUserID: String)
}

/// 从 RevenueCat `CustomerInfo` 提炼出的 PremiumGate 关心的最小信息。
struct RCEntitlementSnapshot: Equatable, Sendable {
    /// entitlement["pro"].isActive
    let isProActive: Bool
    /// entitlement["pro"].expirationDate（永久订阅为 nil）
    let proExpirationDate: Date?
}
```

文件：`Together/Services/Premium/GrantsLoader.swift`

```swift
import Foundation

/// `PremiumGate` 对 Supabase `premium_grants` 表的访问抽象。
protocol GrantsLoaderProtocol: Sendable {
    /// 查询某个用户当前所有未撤销、未过期的 grants。
    /// 失败时抛错。
    func fetchActiveGrants(userID: UUID) async throws -> [PremiumGrant]
}

/// 与数据库行对应的 grants 数据模型。
struct PremiumGrant: Equatable, Sendable, Identifiable {
    let id: UUID
    let userID: UUID
    let category: Category
    let reason: String?
    let grantedAt: Date
    let expiresAt: Date?  // nil = 永久

    enum Category: String, Sendable, Equatable {
        case developer
        case friend
        case grandfather
        case testflight
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -5
```

Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add Together/Services/Premium/RCClientProtocol.swift Together/Services/Premium/GrantsLoader.swift
git commit -m "feat(premium): define RCClientProtocol and GrantsLoaderProtocol

Interface-only commit. Concrete RevenueCatClient and GrantsLoader
implementations come later. Protocols enable testing PremiumGate
with injected stubs."
```

---

## Task 6：`PremiumGate` 合并逻辑（纯函数 + 大量单元测试）

**目的**：实现源无关的 14 天 Grace Period 合并算法。这是整个系统的核心业务逻辑，必须测试覆盖完整。

**Files:**
- Create: `Together/Services/Premium/PremiumGate.swift`（初版，只含静态 `computeStatus`）
- Create: `TogetherTests/PremiumGateMergeTests.swift`

### Step 1: 写失败测试（涵盖 spec § 2.3 algorithm 的 5 个 step）

文件：`TogetherTests/PremiumGateMergeTests.swift`

```swift
import Testing
import Foundation
@testable import Together

@Suite
struct PremiumGateMergeTests {
    private let now = Date(timeIntervalSince1970: 10_000_000)

    private func dateOffset(_ days: Double) -> Date {
        now.addingTimeInterval(days * 86400)
    }

    // MARK: - Step 2: 活跃来源

    @Test func activeRCSubscriptionMakesPro() {
        let status = PremiumGate.computeStatus(
            rcResult: .success(RCEntitlementSnapshot(
                isProActive: true,
                proExpirationDate: dateOffset(30)
            )),
            grantsResult: .success([]),
            cachedStatus: nil,
            now: now
        )
        #expect(status == .pro(source: .subscription, expiresAt: dateOffset(30)))
    }

    @Test func activeGrantMakesPro() {
        let grant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .friend,
            reason: nil, grantedAt: dateOffset(-5), expiresAt: nil
        )
        let status = PremiumGate.computeStatus(
            rcResult: .success(RCEntitlementSnapshot(isProActive: false, proExpirationDate: nil)),
            grantsResult: .success([grant]),
            cachedStatus: nil,
            now: now
        )
        #expect(status == .pro(source: .grant, expiresAt: nil))
    }

    @Test func bothActivePrefersLaterExpiry() {
        let lateGrant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .grandfather,
            reason: nil, grantedAt: dateOffset(-100), expiresAt: nil  // 永久
        )
        let rc = RCEntitlementSnapshot(isProActive: true, proExpirationDate: dateOffset(30))
        let status = PremiumGate.computeStatus(
            rcResult: .success(rc),
            grantsResult: .success([lateGrant]),
            cachedStatus: nil,
            now: now
        )
        // 永久（nil）胜过有限期
        switch status {
        case let .pro(_, expiresAt):
            #expect(expiresAt == nil)
        default:
            Issue.record("expected .pro status, got \(status)")
        }
    }

    // MARK: - Step 3: Grace Period

    @Test func rcExpiredWithin14DaysYieldsGracePeriod() {
        let expired5DaysAgo = dateOffset(-5)
        let rc = RCEntitlementSnapshot(isProActive: false, proExpirationDate: expired5DaysAgo)
        let status = PremiumGate.computeStatus(
            rcResult: .success(rc),
            grantsResult: .success([]),
            cachedStatus: nil,
            now: now
        )
        let expectedLogbookUntil = expired5DaysAgo.addingTimeInterval(14 * 86400)
        #expect(status == .gracePeriod(
            originalExpiry: expired5DaysAgo,
            logbookFullUntil: expectedLogbookUntil
        ))
    }

    @Test func grantExpiredWithin14DaysYieldsGracePeriod() {
        let expired3DaysAgo = dateOffset(-3)
        let grant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .testflight,
            reason: nil, grantedAt: dateOffset(-95), expiresAt: expired3DaysAgo
        )
        let status = PremiumGate.computeStatus(
            rcResult: .success(RCEntitlementSnapshot(isProActive: false, proExpirationDate: nil)),
            grantsResult: .success([grant]),
            cachedStatus: nil,
            now: now
        )
        let expectedLogbookUntil = expired3DaysAgo.addingTimeInterval(14 * 86400)
        #expect(status == .gracePeriod(
            originalExpiry: expired3DaysAgo,
            logbookFullUntil: expectedLogbookUntil
        ))
    }

    @Test func expiredOver14DaysYieldsFree() {
        let rc = RCEntitlementSnapshot(isProActive: false, proExpirationDate: dateOffset(-20))
        let status = PremiumGate.computeStatus(
            rcResult: .success(rc),
            grantsResult: .success([]),
            cachedStatus: nil,
            now: now
        )
        #expect(status == .free)
    }

    @Test func multipleExpiredPicksMostRecent() {
        let olderExpired = dateOffset(-12)
        let recentExpired = dateOffset(-3)
        let olderGrant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .testflight,
            reason: nil, grantedAt: dateOffset(-100), expiresAt: olderExpired
        )
        let rc = RCEntitlementSnapshot(isProActive: false, proExpirationDate: recentExpired)
        let status = PremiumGate.computeStatus(
            rcResult: .success(rc),
            grantsResult: .success([olderGrant]),
            cachedStatus: nil,
            now: now
        )
        // originalExpiry 应是"最晚过期"的那个
        switch status {
        case let .gracePeriod(originalExpiry, _):
            #expect(originalExpiry == recentExpired)
        default:
            Issue.record("expected gracePeriod, got \(status)")
        }
    }

    // MARK: - Step 4: 查询失败 + 缓存

    @Test func bothFailuresUseCache() {
        let cached = PremiumStatus.pro(source: .subscription, expiresAt: dateOffset(5))
        let status = PremiumGate.computeStatus(
            rcResult: .failure(NSError(domain: "test", code: -1)),
            grantsResult: .failure(NSError(domain: "test", code: -1)),
            cachedStatus: cached,
            now: now
        )
        #expect(status == cached)
    }

    @Test func bothFailuresNoCacheReturnsFree() {
        let status = PremiumGate.computeStatus(
            rcResult: .failure(NSError(domain: "test", code: -1)),
            grantsResult: .failure(NSError(domain: "test", code: -1)),
            cachedStatus: nil,
            now: now
        )
        #expect(status == .free)
    }

    @Test func oneFailureOneSuccessIgnoresCacheUsesSuccess() {
        let cached = PremiumStatus.pro(source: .grant, expiresAt: nil)
        let grant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .friend,
            reason: nil, grantedAt: dateOffset(-1), expiresAt: nil
        )
        let status = PremiumGate.computeStatus(
            rcResult: .failure(NSError(domain: "test", code: -1)),
            grantsResult: .success([grant]),
            cachedStatus: cached,
            now: now
        )
        // 成功的 grants 应主导，不使用缓存
        #expect(status == .pro(source: .grant, expiresAt: nil))
    }

    // MARK: - Step 5: 双源无效 + 非 Grace

    @Test func noSourcesReturnsFree() {
        let status = PremiumGate.computeStatus(
            rcResult: .success(RCEntitlementSnapshot(isProActive: false, proExpirationDate: nil)),
            grantsResult: .success([]),
            cachedStatus: nil,
            now: now
        )
        #expect(status == .free)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/PremiumGateMergeTests 2>&1 | tail -10
```

Expected: `PremiumGate` 未定义

### Step 3: 实现（仅 computeStatus 静态函数）

文件：`Together/Services/Premium/PremiumGate.swift`

```swift
import Foundation
import Observation

/// 会员门禁核心。合并 RevenueCat 订阅和 Supabase white-list grants，
/// 暴露可观察的 `PremiumStatus`。
@MainActor
@Observable
final class PremiumGate {
    private(set) var status: PremiumStatus = .unknown

    var isPremium: Bool { (overrideStatus ?? status).isPremium }
    var allowsFullLogbook: Bool { (overrideStatus ?? status).allowsFullLogbook }

    #if DEBUG
    var overrideStatus: PremiumStatus?
    #else
    private var overrideStatus: PremiumStatus? { nil }
    #endif

    // TODO(next task): 注入依赖、生命周期方法

    // MARK: - 合并逻辑（纯函数，便于测试）

    /// 源无关合并：RC 或 grant 任一来源过期 14 天内都进入 Grace Period。
    /// 详见 spec § 2.3 algorithm。
    static func computeStatus(
        rcResult: Result<RCEntitlementSnapshot, Error>,
        grantsResult: Result<[PremiumGrant], Error>,
        cachedStatus: PremiumStatus?,
        now: Date
    ) -> PremiumStatus {
        // Step 1: 收集来源（Source 为 fileprivate 类型，见文件末尾）
        var sources: [Source] = []

        if case let .success(rc) = rcResult, rc.isProActive {
            sources.append(Source(kind: .subscription, expiresAt: rc.proExpirationDate))
        }

        if case let .success(grants) = grantsResult {
            for g in grants {
                // grants 在 loader 层已过滤 revoked & expired，这里直接列入
                sources.append(Source(kind: .grant, expiresAt: g.expiresAt))
            }
        }

        // Step 2: 任一当前有效？
        let active = sources.filter { s in
            guard let expiry = s.expiresAt else { return true }  // nil = 永久 = 有效
            return expiry > now
        }
        if !active.isEmpty {
            let best = pickBest(active)
            return .pro(source: best.kind, expiresAt: best.expiresAt)
        }

        // Step 3: 任一在过去 14 天内失效？
        let graceCandidates = collectRecentlyExpired(
            rcResult: rcResult,
            grantsResult: grantsResult,
            now: now
        )
        if let mostRecent = graceCandidates.max() {
            return .gracePeriod(
                originalExpiry: mostRecent,
                logbookFullUntil: mostRecent.addingTimeInterval(14 * 86400)
            )
        }

        // Step 4: 查询失败，回退缓存
        let rcFailed = (try? rcResult.get()) == nil
        let grantsFailed = (try? grantsResult.get()) == nil
        if rcFailed && grantsFailed, let cached = cachedStatus {
            return cached
        }

        // Step 5: 都无，视为 free
        return .free
    }

    private static func pickBest(_ sources: [Source]) -> Source {
        // 优先永久（expiresAt == nil），其次 expiresAt 最晚，最后 .subscription 破平
        sources.max { lhs, rhs in
            // lhs < rhs 时返回 true (rhs 被选中)
            switch (lhs.expiresAt, rhs.expiresAt) {
            case (nil, nil):
                // 都是永久：subscription 胜过 grant
                return lhs.kind == .grant && rhs.kind == .subscription
            case (nil, _):
                return false  // lhs 永久更大
            case (_, nil):
                return true   // rhs 永久更大
            case let (l?, r?):
                return l < r
            }
        }!
    }

    private static func collectRecentlyExpired(
        rcResult: Result<RCEntitlementSnapshot, Error>,
        grantsResult: Result<[PremiumGrant], Error>,
        now: Date
    ) -> [Date] {
        var result: [Date] = []
        let fourteenDaysAgo = now.addingTimeInterval(-14 * 86400)

        if case let .success(rc) = rcResult,
           !rc.isProActive,
           let expiry = rc.proExpirationDate,
           expiry > fourteenDaysAgo, expiry <= now {
            result.append(expiry)
        }

        if case let .success(grants) = grantsResult {
            for g in grants {
                if let expiry = g.expiresAt,
                   expiry > fourteenDaysAgo, expiry <= now {
                    result.append(expiry)
                }
            }
        }
        return result
    }
}

fileprivate struct Source {
    let kind: PremiumStatus.PremiumSource
    let expiresAt: Date?
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/PremiumGateMergeTests 2>&1 | tail -15
```

Expected: 11 tests passed

- [ ] **Step 5: Commit**

```bash
git add Together/Services/Premium/PremiumGate.swift TogetherTests/PremiumGateMergeTests.swift
git commit -m "feat(premium): add PremiumGate.computeStatus source-agnostic merge

Pure function implementing the 5-step algorithm from spec §2.3:
(1) collect active sources, (2) if any active → .pro, (3) else if any
expired within 14d → .gracePeriod, (4) else if all queries failed but
cache valid → cached, (5) else → .free.

Covered by 11 unit tests including TestFlight grant expiry → grace."
```

---

## Task 7：`PremiumGate` 生命周期（bootstrap / refresh / logOut / 竞态防护）

**目的**：在合并逻辑上加实例状态管理，包括 bootstrap token 防竞态。

**Files:**
- Modify: `Together/Services/Premium/PremiumGate.swift`
- Create: `TogetherTests/PremiumGateLifecycleTests.swift`

### Step 1: 写失败测试

文件：`TogetherTests/PremiumGateLifecycleTests.swift`

```swift
import Testing
import Foundation
@testable import Together

// MARK: - Stub implementations

actor StubRCClient: RCClientProtocol {
    var nextResult: Result<RCEntitlementSnapshot, Error> = .success(
        RCEntitlementSnapshot(isProActive: false, proExpirationDate: nil)
    )
    var configured: Bool = true
    var loggedInID: String?

    nonisolated var isConfigured: Bool { true }
    nonisolated func configure(publicSDKKey: String, appUserID: String) {}
    
    func setNextResult(_ r: Result<RCEntitlementSnapshot, Error>) { nextResult = r }

    func fetchCustomerInfo() async throws -> RCEntitlementSnapshot {
        try nextResult.get()
    }
    func logIn(appUserID: String) async throws { loggedInID = appUserID }
    func logOut() async throws { loggedInID = nil }
}

actor StubGrantsLoader: GrantsLoaderProtocol {
    var nextResult: Result<[PremiumGrant], Error> = .success([])
    var fetchDelay: Duration = .zero

    func setNextResult(_ r: Result<[PremiumGrant], Error>) { nextResult = r }
    func setFetchDelay(_ d: Duration) { fetchDelay = d }

    func fetchActiveGrants(userID: UUID) async throws -> [PremiumGrant] {
        if fetchDelay != .zero {
            try? await Task.sleep(for: fetchDelay)
        }
        return try nextResult.get()
    }
}

// MARK: - Tests

@MainActor
@Suite
struct PremiumGateLifecycleTests {
    private func makeGate(
        rc: StubRCClient = StubRCClient(),
        grants: StubGrantsLoader = StubGrantsLoader(),
        now: Date = Date()
    ) -> (gate: PremiumGate, rc: StubRCClient, grants: StubGrantsLoader) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = PremiumStatusCache(
            defaults: defaults,
            dateProvider: FixedDateProvider(fixed: now)
        )
        let gate = PremiumGate(
            rcClient: rc,
            grantsLoader: grants,
            cache: cache,
            dateProvider: FixedDateProvider(fixed: now)
        )
        return (gate, rc, grants)
    }

    @Test func initialStatusIsUnknown() {
        let (gate, _, _) = makeGate()
        #expect(gate.status == .unknown)
        #expect(gate.isPremium == false)
    }

    @Test func bootstrapWithActiveGrantSetsPro() async {
        let (gate, _, grants) = makeGate()
        let grant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .developer,
            reason: nil, grantedAt: Date(), expiresAt: nil
        )
        await grants.setNextResult(.success([grant]))

        await gate.bootstrap(userID: UUID())
        #expect(gate.isPremium)
        if case let .pro(source, expiresAt) = gate.status {
            #expect(source == .grant)
            #expect(expiresAt == nil)
        } else {
            Issue.record("expected .pro, got \(gate.status)")
        }
    }

    @Test func bootstrapWithAllFailuresAndNoCacheYieldsFree() async {
        let (gate, rc, grants) = makeGate()
        let err = NSError(domain: "test", code: -1)
        await rc.setNextResult(.failure(err))
        await grants.setNextResult(.failure(err))

        await gate.bootstrap(userID: UUID())
        #expect(gate.status == .free)
    }

    @Test func logOutClearsStatusAndCache() async {
        let (gate, _, grants) = makeGate()
        let grant = PremiumGrant(
            id: UUID(), userID: UUID(), category: .friend,
            reason: nil, grantedAt: Date(), expiresAt: nil
        )
        await grants.setNextResult(.success([grant]))
        await gate.bootstrap(userID: UUID())
        #expect(gate.isPremium)

        gate.logOut()
        #expect(gate.status == .unknown)
    }

    #if DEBUG
    @Test func debugOverrideTakesPrecedence() {
        let (gate, _, _) = makeGate()
        // 未 bootstrap 时默认 unknown → 非 premium
        #expect(gate.isPremium == false)

        gate.overrideStatus = .pro(source: .subscription, expiresAt: nil)
        #expect(gate.isPremium)
        #expect(gate.allowsFullLogbook)

        gate.overrideStatus = nil
        #expect(gate.isPremium == false)
    }
    #endif

    @Test func staleBootstrapResultIsDiscarded() async {
        // 快速连续两次 bootstrap，后者应胜出
        let (gate, _, grants) = makeGate()
        let userA = UUID()
        let userB = UUID()

        await grants.setFetchDelay(.milliseconds(100))
        await grants.setNextResult(.success([
            PremiumGrant(
                id: UUID(), userID: userA, category: .developer,
                reason: nil, grantedAt: Date(), expiresAt: nil
            )
        ]))
        let taskA = Task { await gate.bootstrap(userID: userA) }

        // 立刻发起第二次 bootstrap（不同结果）
        try? await Task.sleep(for: .milliseconds(10))
        await grants.setFetchDelay(.zero)
        await grants.setNextResult(.success([]))  // B 没 grants
        await gate.bootstrap(userID: userB)

        // 等 A 完成
        await taskA.value

        // 最终 status 应是 B 的（.free），不是 A 的 .pro
        #expect(gate.status == .free)
    }
}
```

- [ ] **Step 2: 运行确认失败**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/PremiumGateLifecycleTests 2>&1 | tail -10
```

Expected: `PremiumGate.init(rcClient:grantsLoader:cache:dateProvider:)` 和 `bootstrap` 等方法未定义

### Step 3: 扩展 PremiumGate

修改 `Together/Services/Premium/PremiumGate.swift`，在类内添加：

```swift
// 追加到 @Observable final class PremiumGate 里

// MARK: - Dependencies
private let rcClient: RCClientProtocol
private let grantsLoader: GrantsLoaderProtocol
private let cache: PremiumStatusCache
private let dateProvider: DateProvider

// MARK: - Race protection
private var bootstrapToken = UUID()
private var currentUserID: UUID?

init(
    rcClient: RCClientProtocol,
    grantsLoader: GrantsLoaderProtocol,
    cache: PremiumStatusCache,
    dateProvider: DateProvider
) {
    self.rcClient = rcClient
    self.grantsLoader = grantsLoader
    self.cache = cache
    self.dateProvider = dateProvider
}

// MARK: - Lifecycle

func bootstrap(userID: UUID) async {
    currentUserID = userID
    let token = UUID()
    bootstrapToken = token

    async let rcResult = safeFetchRC()
    async let grantsResult = safeFetchGrants(userID: userID)
    let (rc, grants) = await (rcResult, grantsResult)

    // 竞态防护：只有 token 仍是最新的才应用结果
    guard bootstrapToken == token else { return }

    let cached = cache.load()
    let newStatus = Self.computeStatus(
        rcResult: rc, grantsResult: grants,
        cachedStatus: cached,
        now: dateProvider.now()
    )
    status = newStatus
    cache.save(newStatus)
}

func refresh() async {
    guard let userID = currentUserID else { return }
    await bootstrap(userID: userID)
}

func logOut() {
    bootstrapToken = UUID()  // 使任何 in-flight 的 bootstrap 作废
    currentUserID = nil
    status = .unknown
    cache.clear()
}

// MARK: - Safe wrappers

private func safeFetchRC() async -> Result<RCEntitlementSnapshot, Error> {
    do {
        let info = try await rcClient.fetchCustomerInfo()
        return .success(info)
    } catch {
        return .failure(error)
    }
}

private func safeFetchGrants(userID: UUID) async -> Result<[PremiumGrant], Error> {
    do {
        let grants = try await grantsLoader.fetchActiveGrants(userID: userID)
        return .success(grants)
    } catch {
        return .failure(error)
    }
}
```

- [ ] **Step 4: 运行测试**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/PremiumGateLifecycleTests 2>&1 | tail -15
```

Expected: 6 tests passed

- [ ] **Step 5: Commit**

```bash
git add Together/Services/Premium/PremiumGate.swift TogetherTests/PremiumGateLifecycleTests.swift
git commit -m "feat(premium): add PremiumGate lifecycle (bootstrap/refresh/logOut)

Adds DI-friendly init + async bootstrap that merges RC + grants + cache
via computeStatus. Includes bootstrapToken race protection: if two
bootstrap calls overlap, only the latest token's result is applied.

#if DEBUG overrideStatus takes precedence over computed status
(consumed by ProfileDebugSection in Task 21)."
```

---

## Task 8：Supabase `premium_grants` 表 migration

**目的**：建表 + 索引 + RLS。独立于 iOS 代码，可并行推进。

**Files:**
- Create: `supabase/config.toml`（可用 `supabase init` 生成，但 MVP 可直接手写最小版）
- Create: `supabase/migrations/<timestamp>_premium_grants.sql`

### Step 1: 准备 Supabase 目录

```bash
mkdir -p supabase/migrations
```

如果要走完整 CLI 工作流（推荐），在项目根目录运行：

```bash
# 需要先安装 Supabase CLI: brew install supabase/tap/supabase
supabase init
```

这会生成 `supabase/config.toml`。**MVP 阶段若 CLI 未安装**，可以跳过 `init`，直接建 migration SQL 文件，后续在 Supabase Dashboard 手工粘 SQL 执行。

- [ ] **Step 2: 创建 migration SQL**

文件：`supabase/migrations/20260422000001_premium_grants.sql`

（时间戳格式 `YYYYMMDDHHMMSS` + 递增序号，此处取当天 00:00:01）

```sql
-- Phase 2 Premium Infrastructure
-- Source spec: docs/superpowers/specs/2026-04-22-premium-infrastructure-design.md §3

-- =====================================================================
-- Table
-- =====================================================================
CREATE TABLE premium_grants (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category    text NOT NULL CHECK (category IN ('developer', 'friend', 'grandfather', 'testflight')),
    reason      text,
    granted_at  timestamptz NOT NULL DEFAULT now(),
    expires_at  timestamptz,
    revoked_at  timestamptz,
    granted_by  text,
    metadata    jsonb NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE premium_grants IS 
    'White-list grants for Together Pro. Coexists with RevenueCat subscriptions; merged client-side.';
COMMENT ON COLUMN premium_grants.category IS 
    'developer | friend | grandfather | testflight';
COMMENT ON COLUMN premium_grants.expires_at IS 
    'NULL means permanent grant';
COMMENT ON COLUMN premium_grants.revoked_at IS 
    'Soft-delete timestamp. Client queries filter WHERE revoked_at IS NULL.';

-- =====================================================================
-- Indexes
-- =====================================================================
CREATE INDEX idx_premium_grants_user_id ON premium_grants(user_id);
CREATE INDEX idx_premium_grants_active 
    ON premium_grants(user_id, expires_at) 
    WHERE revoked_at IS NULL;

-- =====================================================================
-- Row-Level Security
-- =====================================================================
ALTER TABLE premium_grants ENABLE ROW LEVEL SECURITY;

-- Users can only SELECT their own grants
CREATE POLICY "users_read_own_grants"
    ON premium_grants FOR SELECT
    USING (auth.uid() = user_id);

-- No INSERT / UPDATE / DELETE policies for authenticated role.
-- Only service_role (Dashboard, CLI, migration scripts) can mutate.
```

- [ ] **Step 3: 应用 migration**

两种方式：

**(a) Supabase CLI（推荐）**

```bash
supabase link --project-ref <your-project-ref>   # 首次
supabase db push                                  # 推送 migrations
```

**(b) Dashboard 手工执行**

1. 打开 Supabase Dashboard → 你的项目 → SQL Editor
2. 粘贴 `supabase/migrations/20260422000001_premium_grants.sql` 内容
3. 点击 Run

- [ ] **Step 4: 验证表结构**

在 Supabase Dashboard SQL Editor 运行：

```sql
-- 验证表存在
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'premium_grants'
ORDER BY ordinal_position;

-- 验证 RLS 启用
SELECT relrowsecurity FROM pg_class WHERE relname = 'premium_grants';
-- Expected: t

-- 验证索引
SELECT indexname FROM pg_indexes WHERE tablename = 'premium_grants';
-- Expected: idx_premium_grants_user_id, idx_premium_grants_active, premium_grants_pkey

-- 测试插入（作为 service_role）
INSERT INTO premium_grants (user_id, category, reason, granted_by)
VALUES ('<你自己的 user_id>', 'developer', 'Dogfood test', 'manual-setup');

-- 测试 RLS（作为 authenticated role，应只能看到自己的）
SELECT * FROM premium_grants;
```

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260422000001_premium_grants.sql supabase/config.toml
git commit -m "feat(supabase): add premium_grants table migration

Table schema + indexes + RLS per spec §3. Supports 4 grant categories
(developer/friend/grandfather/testflight), soft-delete via revoked_at,
NULL expires_at = permanent.

RLS allows users to SELECT their own grants; only service_role can
INSERT/UPDATE/DELETE (via Dashboard or migration scripts)."
```

---

## Task 9：添加 RevenueCat SPM 依赖

**目的**：把 `purchases-ios` 作为 Swift Package 加入项目。

**Files:**
- Modify: `Together.xcodeproj/project.pbxproj`（自动）
- Modify: `Together.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`（自动）

### Step 1: 在 Xcode 里添加依赖

打开 Xcode，执行：

1. **File → Add Package Dependencies…**
2. 粘贴 URL：`https://github.com/RevenueCat/purchases-ios`
3. **Dependency Rule**：Up to Next Major Version → `5.0.0`
4. **Add Package**
5. 选择 products：勾选 `RevenueCat`，Target 设为 `Together`
6. **Add Package**

- [ ] **Step 2: 验证 build 通过**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -10
```

Expected: Build succeeded

- [ ] **Step 3: 临时导入验证**

在 `Together/App/AppContext.swift` 顶部临时加一行：

```swift
import RevenueCat
```

重新 build。若编译通过，说明 SPM 正确接入。验证完删除该 import（后续 Task 10 才会真正用到）。

- [ ] **Step 4: Commit**

```bash
git add Together.xcodeproj/
git commit -m "chore(deps): add RevenueCat SPM dependency (purchases-ios 5.x)"
```

---

## Task 10：`RevenueCatConfig` 常量

**目的**：集中管理 RC 相关常量（public SDK key、entitlement id）。

**Files:**
- Create: `Together/Services/Premium/RevenueCatConfig.swift`

### Step 1: 写文件

文件：`Together/Services/Premium/RevenueCatConfig.swift`

```swift
import Foundation

/// RevenueCat 相关常量。所有地方引用这里，避免魔法字符串。
enum RevenueCatConfig {
    /// RevenueCat Dashboard → Project → API Keys → Public SDK Keys → iOS
    ///
    /// 注意：public SDK key 可以安全硬编码（设计上如此，类似 Supabase anon key）。
    /// 正式上线前需替换为 production key（RC 区分 sandbox/production）。
    static let publicSDKKey: String = "appl_REPLACE_WITH_REAL_KEY"

    /// Entitlement 标识符。必须与 RC Dashboard 中创建的 entitlement ID 一致。
    static let entitlementIdentifier: String = "pro"
}
```

**重要**：在 Track D1 RevenueCat 账号注册完成后，用户需要回来把 `appl_REPLACE_WITH_REAL_KEY` 替换为真实 key。这是一次性的配置。

- [ ] **Step 2: 编译验证**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Together/Services/Premium/RevenueCatConfig.swift
git commit -m "feat(premium): add RevenueCatConfig constants (key + entitlement id)

Public SDK key is a placeholder; replace with real key from RevenueCat
Dashboard before TestFlight build."
```

---

## Task 11：`RevenueCatClient`（`RCClientProtocol` 的真实实现）

**目的**：把 RevenueCat SDK 包装成符合 `RCClientProtocol` 的具体类。

**Files:**
- Create: `Together/Services/Premium/RevenueCatClient.swift`

### Step 1: 写实现

文件：`Together/Services/Premium/RevenueCatClient.swift`

```swift
import Foundation
import RevenueCat

/// `RCClientProtocol` 的生产实现，封装 `Purchases` 单例。
final class RevenueCatClient: RCClientProtocol {
    nonisolated var isConfigured: Bool { Purchases.isConfigured }

    nonisolated func configure(publicSDKKey: String, appUserID: String) {
        Purchases.configure(withAPIKey: publicSDKKey, appUserID: appUserID)
    }

    func fetchCustomerInfo() async throws -> RCEntitlementSnapshot {
        let info = try await Purchases.shared.customerInfo()
        let entitlement = info.entitlements[RevenueCatConfig.entitlementIdentifier]
        return RCEntitlementSnapshot(
            isProActive: entitlement?.isActive ?? false,
            proExpirationDate: entitlement?.expirationDate
        )
    }

    func logIn(appUserID: String) async throws {
        _ = try await Purchases.shared.logIn(appUserID)
    }

    func logOut() async throws {
        _ = try await Purchases.shared.logOut()
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -5
```

Expected: Build succeeded（`RevenueCat` import 成功、API 调用签名正确）

- [ ] **Step 3: Commit**

```bash
git add Together/Services/Premium/RevenueCatClient.swift
git commit -m "feat(premium): add RevenueCatClient conforming to RCClientProtocol

Thin wrapper over Purchases.shared for customerInfo / login / logout.
Extracts entitlement[pro] into RCEntitlementSnapshot for PremiumGate."
```

---

## Task 12：`SupabaseGrantsLoader`（`GrantsLoaderProtocol` 的真实实现）

**目的**：用 supabase-swift SDK 查询 `premium_grants` 表。

**Files:**
- Modify: `Together/Services/Premium/GrantsLoader.swift`（在同文件追加具体实现）

### Step 1: 看一眼 SupabaseClient 怎么用

```bash
cat Together/Services/Auth/SupabaseClient.swift | head -30
```

观察：`SupabaseClientProvider.shared.client` 返回一个 `SupabaseClient` 实例。后续查询通过 `.from("表名").select().execute()`。

### Step 2: 追加具体实现

修改 `Together/Services/Premium/GrantsLoader.swift`，在文件末尾追加：

```swift
import Supabase

/// 基于 supabase-swift SDK 的 `GrantsLoaderProtocol` 实现。
final class SupabaseGrantsLoader: GrantsLoaderProtocol {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchActiveGrants(userID: UUID) async throws -> [PremiumGrant] {
        // 过滤掉 revoked 和已过期的 grants
        let rows: [GrantRow] = try await client
            .from("premium_grants")
            .select()
            .eq("user_id", value: userID.uuidString)
            .is("revoked_at", value: nil)
            .or("expires_at.is.null,expires_at.gt.\(ISO8601DateFormatter().string(from: Date()))")
            .execute()
            .value

        return rows.compactMap { try? $0.toDomain() }
    }
}

// MARK: - DB row DTO

private struct GrantRow: Decodable {
    let id: UUID
    let user_id: UUID
    let category: String
    let reason: String?
    let granted_at: String       // ISO8601
    let expires_at: String?

    func toDomain() throws -> PremiumGrant {
        guard let cat = PremiumGrant.Category(rawValue: category) else {
            throw GrantDecodeError.unknownCategory(category)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let grantedDate = formatter.date(from: granted_at)
            ?? ISO8601DateFormatter().date(from: granted_at)
            ?? Date()
        let expiryDate = expires_at.flatMap { formatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        return PremiumGrant(
            id: id, userID: user_id, category: cat, reason: reason,
            grantedAt: grantedDate, expiresAt: expiryDate
        )
    }
}

enum GrantDecodeError: Error, Equatable {
    case unknownCategory(String)
}
```

- [ ] **Step 3: 编译验证**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Together/Services/Premium/GrantsLoader.swift
git commit -m "feat(premium): add SupabaseGrantsLoader for premium_grants queries

Filters out revoked (revoked_at NOT NULL) and expired (expires_at <= now)
rows at the SQL level so PremiumGate.computeStatus can trust all
returned grants are currently valid.

ISO8601 parsing handles both with and without fractional seconds."
```

---

## Task 13：`AppContainer` 持有 `PremiumGate`

**目的**：让 `PremiumGate` 成为应用级单例，通过 `AppContainer` 注入各处。

**Files:**
- Modify: `Together/App/AppContainer.swift`

### Step 1: 看现状

```bash
grep -n "let .*=\|var .*=\|init" Together/App/AppContainer.swift | head -30
```

观察现有 `AppContainer` 持有的依赖模式（例如可能有 `sessionStore`、`supabaseClient` 等）。

### Step 2: 添加 premiumGate 属性和构造

修改 `Together/App/AppContainer.swift`，在 `AppContainer` 类里追加：

```swift
// 追加到 AppContainer 的属性区
let premiumGate: PremiumGate

// 在 init 或 build 方法里追加
private static func makePremiumGate(
    supabaseClient: SupabaseClient
) -> PremiumGate {
    let rcClient = RevenueCatClient()
    let grantsLoader = SupabaseGrantsLoader(client: supabaseClient)
    let cache = PremiumStatusCache(
        defaults: .standard,
        dateProvider: SystemDateProvider()
    )
    return PremiumGate(
        rcClient: rcClient,
        grantsLoader: grantsLoader,
        cache: cache,
        dateProvider: SystemDateProvider()
    )
}

// 在 AppContainer 的 init 最后追加：
// self.premiumGate = Self.makePremiumGate(supabaseClient: supabaseClient)
```

**具体集成**：取决于 `AppContainer` 现有结构。打开文件阅读，找到"构造完所有依赖后的汇总处"，插入 `premiumGate` 的构造。确保它能接到 `supabaseClient`（如果现有 AppContainer 已持有）。

- [ ] **Step 3: 编译验证**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Together/App/AppContainer.swift
git commit -m "feat(premium): wire PremiumGate into AppContainer

Assembles PremiumGate dependencies: RevenueCatClient + SupabaseGrantsLoader
+ PremiumStatusCache + SystemDateProvider. Stored as app-level singleton
on AppContainer, to be injected into ViewModels via AppContext."
```

---

## Task 14：`AppContext` 生命周期挂钩

**目的**：在登录/登出/前后台切换时驱动 PremiumGate 刷新。

**Files:**
- Modify: `Together/App/AppContext.swift`

### Step 1: 看现有 lifecycle 挂钩

```bash
grep -n "handleSignIn\|clearForSignOut\|postLaunch\|scenePhase" Together/App/AppContext.swift
```

### Step 2: 追加 PremiumGate 管理方法

在 `AppContext.swift` 的 extension 中追加：

```swift
// MARK: - Premium lifecycle

extension AppContext {
    /// 登录后或冷启动且已登录时调用。
    func configurePremiumGate() async {
        guard let user = sessionStore.currentUser else { return }

        let rcClient = container.premiumGate.rcClient as? RevenueCatClient
        // 首次 configure 或切换用户
        if !Purchases.isConfigured {
            Purchases.configure(
                withAPIKey: RevenueCatConfig.publicSDKKey,
                appUserID: user.id.uuidString
            )
        } else {
            _ = try? await Purchases.shared.logIn(user.id.uuidString)
        }

        await container.premiumGate.bootstrap(userID: user.id)
    }

    /// 登出时调用。
    func teardownPremiumGate() async {
        _ = try? await Purchases.shared.logOut()
        container.premiumGate.logOut()
    }

    /// 前台激活时调用（条件刷新：距上次 > 1 小时才真正 refresh）。
    func refreshPremiumGateIfStale() async {
        guard shouldRefreshPremiumGate() else { return }
        await container.premiumGate.refresh()
        lastPremiumRefreshAt = Date()
    }

    private static let refreshInterval: TimeInterval = 3600
    private func shouldRefreshPremiumGate() -> Bool {
        guard let last = lastPremiumRefreshAt else { return true }
        return Date().timeIntervalSince(last) > Self.refreshInterval
    }
}
```

**注意**：`lastPremiumRefreshAt` 需要作为 AppContext 的属性。由于上面示意需要 `container` 暴露 `premiumGate`，而 `PremiumGate.rcClient` 不应该是 public —— 这里我们让 AppContext 直接访问 `Purchases` 全局 API 即可，**不需要**通过 gate 访问 rcClient。删掉 `rcClient as? RevenueCatClient` 这一行重新整理如下：

修正后的追加代码：

```swift
// MARK: - Premium lifecycle

import RevenueCat

extension AppContext {
    func configurePremiumGate() async {
        guard let user = sessionStore.currentUser else { return }

        if !Purchases.isConfigured {
            Purchases.configure(
                withAPIKey: RevenueCatConfig.publicSDKKey,
                appUserID: user.id.uuidString
            )
        } else {
            _ = try? await Purchases.shared.logIn(user.id.uuidString)
        }
        await container.premiumGate.bootstrap(userID: user.id)
    }

    func teardownPremiumGate() async {
        _ = try? await Purchases.shared.logOut()
        container.premiumGate.logOut()
        lastPremiumRefreshAt = nil
    }

    func refreshPremiumGateIfStale() async {
        if let last = lastPremiumRefreshAt, Date().timeIntervalSince(last) < 3600 {
            return
        }
        await container.premiumGate.refresh()
        lastPremiumRefreshAt = Date()
    }
}
```

并在 `AppContext` 类内添加：

```swift
// 追加属性
private var lastPremiumRefreshAt: Date?
```

### Step 3: 在已有 lifecycle 点调用

找到 `AppContext.postLaunchWorkIfNeeded()`（或 `SessionStore.handleSignIn` 完成回调处），追加：

```swift
Task { await configurePremiumGate() }
```

找到登出路径（如 `clearForSignOut()` 前后），追加：

```swift
Task { await teardownPremiumGate() }
```

找到 `scenePhase` 观察点（通常在 App 结构体里），追加：

```swift
.onChange(of: scenePhase) { _, newValue in
    if newValue == .active {
        Task { await appContext.refreshPremiumGateIfStale() }
    }
}
```

- [ ] **Step 4: 编译验证 + Smoke Test**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -5
```

手动 smoke test：

1. 模拟器启动 App
2. 登录
3. 观察控制台（添加临时 print 确认 `bootstrap` 被调用）
4. 登出
5. 观察 `teardown` 被调用

- [ ] **Step 5: Commit**

```bash
git add Together/App/AppContext.swift
git commit -m "feat(premium): wire PremiumGate lifecycle into AppContext

- configurePremiumGate() on sign-in / cold launch when authenticated
- teardownPremiumGate() on sign-out
- refreshPremiumGateIfStale() on scene activation (1h debounce)

RC SDK configured lazily on first call; subsequent user switches go
through Purchases.logIn()."
```

---

## Task 15：`SyncEngineCoordinator` 加 `isPremium` guard

**目的**：跨设备同步只对 Pro 用户启动。

**Files:**
- Modify: `Together/Sync/Engine/SyncEngineCoordinator.swift`（L60 附近）
- Create: `TogetherTests/SyncEngineCoordinatorGuardTests.swift`

### Step 1: 看 SyncEngineCoordinator 现有签名

```bash
sed -n '55,75p' Together/Sync/Engine/SyncEngineCoordinator.swift
```

观察 `startSoloSync()` 的完整签名和现有 guard（如果有 `isRunningSolo` 检查）。

### Step 2: 写失败测试

文件：`TogetherTests/SyncEngineCoordinatorGuardTests.swift`

```swift
import Testing
import Foundation
@testable import Together

@MainActor
@Suite
struct SyncEngineCoordinatorGuardTests {
    @Test func doesNotStartWhenNotPremium() async {
        let (coordinator, gate) = makeCoordinator()
        // gate 默认 .unknown → isPremium false
        await coordinator.startSoloSync()
        #expect(coordinator.isRunningSolo == false)
    }

    @Test func startsWhenPremium() async {
        let (coordinator, gate) = makeCoordinator()
        gate.overrideStatus = .pro(source: .subscription, expiresAt: nil)
        await coordinator.startSoloSync()
        #expect(coordinator.isRunningSolo)
    }

    // 辅助：组装一个能测的 SyncEngineCoordinator + PremiumGate
    private func makeCoordinator() -> (SyncEngineCoordinator, PremiumGate) {
        let rc = StubRCClient()
        let grants = StubGrantsLoader()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = PremiumStatusCache(defaults: defaults, dateProvider: SystemDateProvider())
        let gate = PremiumGate(
            rcClient: rc, grantsLoader: grants,
            cache: cache, dateProvider: SystemDateProvider()
        )
        let coordinator = SyncEngineCoordinator(
            /* 其他依赖按现有 init 签名补齐 */
            premiumGate: gate
        )
        return (coordinator, gate)
    }
}
```

**注意**：`SyncEngineCoordinator` 的构造函数需要扩展接受 `premiumGate`。完整 init 签名依赖项目现状，Step 3 会调整。

- [ ] **Step 3: 修改 SyncEngineCoordinator**

修改 `Together/Sync/Engine/SyncEngineCoordinator.swift`：

1. 在 init 签名里添加 `premiumGate: PremiumGate`
2. 存为 private 属性 `private let premiumGate: PremiumGate`
3. 在 `startSoloSync()`（L60）开头加 guard：

```swift
func startSoloSync() {
    guard premiumGate.isPremium else { return }   // ← 新增
    guard !isRunningSolo else { return }           // 原有
    // ... 原有启动逻辑
}
```

在 `AppContainer`（或 `AppContext`）构造 `SyncEngineCoordinator` 的地方，传入 `premiumGate`。

- [ ] **Step 4: 运行测试**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/SyncEngineCoordinatorGuardTests 2>&1 | tail -10
```

Expected: 2 tests passed

- [ ] **Step 5: Commit**

```bash
git add Together/Sync/Engine/SyncEngineCoordinator.swift Together/App/AppContainer.swift TogetherTests/SyncEngineCoordinatorGuardTests.swift
git commit -m "feat(premium): gate SyncEngineCoordinator.startSoloSync on isPremium

Non-Pro users: silent early-return, CKSyncEngine never spins up.
Upsell CTA for non-Pro on a second device is handled in Phase 3
UI (product spec §3), not via error channel here."
```

---

## Task 16：`ItemRepository` 协议加 `since:` 参数

**目的**：为 Logbook 30 天过滤在底层开口。

**Files:**
- Modify: `Together/Services/Items/ItemRepository.swift`
- Modify: `Together/Services/Items/LocalItemRepository.swift`
- Modify: `Together/Services/Items/MockItemRepository.swift`
- Modify: `Together/Sync/SupabaseSyncService.swift`（若该文件也实现了 fetchCompletedItems）

### Step 1: 修改 protocol

找到 `Together/Services/Items/ItemRepository.swift` 里 `fetchCompletedItems` 的定义。修改签名：

```swift
// 旧
func fetchCompletedItems(
    spaceID: UUID,
    searchText: String?,
    before: Date?,
    limit: Int
) async throws -> [Item]

// 新
func fetchCompletedItems(
    spaceID: UUID,
    searchText: String?,
    before: Date?,
    since: Date? = nil,            // ← 新增参数，默认 nil 保持向后兼容
    limit: Int
) async throws -> [Item]
```

### Step 2: 修改所有实现

分别修改：

- `Together/Services/Items/LocalItemRepository.swift`：在 SwiftData predicate 里追加 `if let since { predicate AND completedAt >= since }`
- `Together/Services/Items/MockItemRepository.swift`：在内存 filter 里追加 `.filter { if let since { $0.completedAt >= since } else { true } }`
- `Together/Sync/SupabaseSyncService.swift`（如适用）：在 Supabase query 里追加 `.gte("completed_at", value: since)` when非 nil

具体实现代码随现有代码风格调整。**DRY 原则**：每个实现的 predicate/filter 构造处追加同一个条件。

- [ ] **Step 3: 编译验证**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -10
```

Expected: Build succeeded（所有调用方默认传 `since: nil` 依然工作）

- [ ] **Step 4: Commit**

```bash
git add Together/Services/Items/ItemRepository.swift Together/Services/Items/LocalItemRepository.swift Together/Services/Items/MockItemRepository.swift Together/Sync/SupabaseSyncService.swift
git commit -m "feat(items): add since: parameter to fetchCompletedItems

Optional, defaults to nil for backwards compatibility. When non-nil,
filters results to items with completedAt >= since. Used by
CompletedHistoryViewModel to enforce 30-day free-tier cap."
```

---

## Task 17：`CompletedHistoryViewModel` 接入 `PremiumGate`

**目的**：非 Pro 用户加载 Logbook 时自动带 30 天 floor。

**Files:**
- Modify: `Together/Features/Profile/CompletedHistoryViewModel.swift`
- Create: `TogetherTests/CompletedHistoryViewModelSinceTests.swift`

### Step 1: 看现状

```bash
sed -n '85,110p' Together/Features/Profile/CompletedHistoryViewModel.swift
```

观察 `fetchCompletedItems` 调用处（L95）。

### Step 2: 写失败测试

文件：`TogetherTests/CompletedHistoryViewModelSinceTests.swift`

```swift
import Testing
import Foundation
@testable import Together

@MainActor
@Suite
struct CompletedHistoryViewModelSinceTests {
    @Test func freePassesThirtyDayFloor() async throws {
        let (vm, repo, gate) = makeViewModel()
        // gate 默认非 premium
        await vm.loadFirstPage()
        let capturedSince = await repo.lastSinceArg
        #expect(capturedSince != nil)
        // since 应在 29-31 天前范围内（允许测试执行时间容差）
        if let s = capturedSince {
            let daysAgo = Date().timeIntervalSince(s) / 86400
            #expect(daysAgo >= 29.9 && daysAgo <= 30.1)
        }
    }

    @Test func proPassesNoFloor() async throws {
        let (vm, repo, gate) = makeViewModel()
        gate.overrideStatus = .pro(source: .subscription, expiresAt: nil)
        await vm.loadFirstPage()
        let capturedSince = await repo.lastSinceArg
        #expect(capturedSince == nil)
    }

    @Test func gracePeriodPassesNoFloor() async throws {
        let (vm, repo, gate) = makeViewModel()
        let now = Date()
        gate.overrideStatus = .gracePeriod(
            originalExpiry: now.addingTimeInterval(-5 * 86400),
            logbookFullUntil: now.addingTimeInterval(9 * 86400)
        )
        await vm.loadFirstPage()
        let capturedSince = await repo.lastSinceArg
        #expect(capturedSince == nil)
    }

    // MARK: - Helpers

    private func makeViewModel() -> (CompletedHistoryViewModel, CapturingItemRepository, PremiumGate) {
        let repo = CapturingItemRepository()
        let rc = StubRCClient()
        let grants = StubGrantsLoader()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = PremiumStatusCache(defaults: defaults, dateProvider: SystemDateProvider())
        let gate = PremiumGate(rcClient: rc, grantsLoader: grants, cache: cache, dateProvider: SystemDateProvider())
        let vm = CompletedHistoryViewModel(
            /* 其他依赖按现有 init 补齐 */
            itemRepository: repo,
            premiumGate: gate
        )
        return (vm, repo, gate)
    }
}

actor CapturingItemRepository: ItemRepository {
    private(set) var lastSinceArg: Date?
    // ... 实现其他 protocol 要求的方法（stub 版）

    func fetchCompletedItems(
        spaceID: UUID, searchText: String?, before: Date?,
        since: Date?, limit: Int
    ) async throws -> [Item] {
        lastSinceArg = since
        return []
    }
    // 其他方法：throw 或返回空，不关心
}
```

**注意**：`CapturingItemRepository` 需要实现 `ItemRepository` 全部方法。按最小可运行版本，其他方法返回空数据或 throw `notImplemented`。

- [ ] **Step 3: 修改 ViewModel**

1. 在 `CompletedHistoryViewModel` 类里添加 `private let premiumGate: PremiumGate` 属性
2. 修改 init 加入 `premiumGate: PremiumGate` 参数
3. 修改 `fetchCompletedItems` 调用处（约 L95）：

```swift
// 旧
let items = try await itemRepository.fetchCompletedItems(
    spaceID: spaceID,
    searchText: searchText,
    before: before,
    limit: pageSize
)

// 新
let since: Date? = premiumGate.allowsFullLogbook
    ? nil
    : Calendar.current.date(byAdding: .day, value: -30, to: Date())

let items = try await itemRepository.fetchCompletedItems(
    spaceID: spaceID,
    searchText: searchText,
    before: before,
    since: since,
    limit: pageSize
)
```

4. 在 `AppContext` 构造 `CompletedHistoryViewModel` 的地方传入 `premiumGate`

- [ ] **Step 4: 运行测试**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/CompletedHistoryViewModelSinceTests 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Profile/CompletedHistoryViewModel.swift Together/App/AppContext.swift TogetherTests/CompletedHistoryViewModelSinceTests.swift
git commit -m "feat(premium): gate Logbook history with 30-day floor for non-Pro

CompletedHistoryViewModel now computes since: based on
premiumGate.allowsFullLogbook. Pro and gracePeriod pass nil (full
history); free passes now-30d."
```

---

## Task 18：`ImportantDatesViewModel` 拆分 `save()` + 配额门禁

**目的**：新建纪念日时判断本人配额，达 5 个触发 upsell。

**Files:**
- Modify: `Together/Features/Anniversaries/ImportantDatesViewModel.swift`
- Modify: `Together/Features/Anniversaries/ImportantDateEditSheet.swift`（调用方）
- Create: `TogetherTests/ImportantDatesViewModelQuotaTests.swift`

### Step 1: 看现状

```bash
sed -n '30,50p' Together/Features/Anniversaries/ImportantDatesViewModel.swift
```

观察现有 `save()` 签名与调用方式。

### Step 2: 写失败测试

文件：`TogetherTests/ImportantDatesViewModelQuotaTests.swift`

```swift
import Testing
import Foundation
@testable import Together

@MainActor
@Suite
struct ImportantDatesViewModelQuotaTests {
    private let me = UUID()
    private let partner = UUID()

    @Test func freeUnderQuotaAllowsCreate() async throws {
        let (vm, gate) = makeViewModel(existingCountByMe: 4)
        // gate 默认非 premium
        try await vm.createNew(makeDraft())
        #expect(vm.pendingUpsellTrigger == nil)
        #expect(vm.events.count == 5)
    }

    @Test func freeAtQuotaBlocksCreate() async throws {
        let (vm, gate) = makeViewModel(existingCountByMe: 5)
        try await vm.createNew(makeDraft())
        #expect(vm.pendingUpsellTrigger == .anniversaryQuota)
        #expect(vm.events.count == 5)  // 未新增
    }

    @Test func proBypassesQuota() async throws {
        let (vm, gate) = makeViewModel(existingCountByMe: 10)
        gate.overrideStatus = .pro(source: .subscription, expiresAt: nil)
        try await vm.createNew(makeDraft())
        #expect(vm.pendingUpsellTrigger == nil)
        #expect(vm.events.count == 11)
    }

    @Test func partnersObjectsDontCountAgainstMe() async throws {
        let (vm, gate) = makeViewModel(
            existingCountByMe: 4,
            existingCountByPartner: 100  // 对方创建 100 个，不占我的配额
        )
        try await vm.createNew(makeDraft())
        #expect(vm.pendingUpsellTrigger == nil)
        #expect(vm.events.filter { $0.creatorID == me }.count == 5)
    }

    @Test func dismissUpsellClearsTrigger() async throws {
        let (vm, _) = makeViewModel(existingCountByMe: 5)
        try? await vm.createNew(makeDraft())
        #expect(vm.pendingUpsellTrigger == .anniversaryQuota)
        vm.dismissUpsell()
        #expect(vm.pendingUpsellTrigger == nil)
    }

    // MARK: - Helpers

    private func makeDraft() -> ImportantDateDraft {
        // 依据项目实际 ImportantDateDraft 结构构造
        ImportantDateDraft(
            title: "Test",
            kind: .custom,
            dateValue: Date(),
            recurrence: .none,
            notifyDaysBefore: 7,
            notifyOnDay: true,
            icon: nil,
            presetHolidayID: nil
        )
    }

    private func makeViewModel(
        existingCountByMe: Int,
        existingCountByPartner: Int = 0
    ) -> (ImportantDatesViewModel, PremiumGate) {
        let sessionStore = SessionStore()
        // 设置 currentUser = me（根据实际 SessionStore API）
        
        let repo = MockImportantDateRepository()  // 或现有 mock
        let events = Self.makeExisting(
            meID: me,
            partnerID: partner,
            meCount: existingCountByMe,
            partnerCount: existingCountByPartner
        )
        
        let rc = StubRCClient()
        let grants = StubGrantsLoader()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = PremiumStatusCache(defaults: defaults, dateProvider: SystemDateProvider())
        let gate = PremiumGate(rcClient: rc, grantsLoader: grants, cache: cache, dateProvider: SystemDateProvider())
        
        let vm = ImportantDatesViewModel(
            sessionStore: sessionStore,
            premiumGate: gate,
            repository: repo
            // 其他依赖按现有 init 补
        )
        vm.events = events
        return (vm, gate)
    }

    private static func makeExisting(
        meID: UUID, partnerID: UUID,
        meCount: Int, partnerCount: Int
    ) -> [ImportantDate] {
        let spaceID = UUID()
        return (0..<meCount).map { i in
            ImportantDate(
                id: UUID(), spaceID: spaceID, creatorID: meID,
                kind: .custom, title: "Mine \(i)",
                dateValue: Date(), recurrence: .none,
                notifyDaysBefore: 7, notifyOnDay: true,
                icon: nil, presetHolidayID: nil,
                updatedAt: Date()
            )
        } + (0..<partnerCount).map { i in
            ImportantDate(
                id: UUID(), spaceID: spaceID, creatorID: partnerID,
                kind: .custom, title: "Partner \(i)",
                dateValue: Date(), recurrence: .none,
                notifyDaysBefore: 7, notifyOnDay: true,
                icon: nil, presetHolidayID: nil,
                updatedAt: Date()
            )
        }
    }
}
```

### Step 3: 修改 ViewModel

修改 `Together/Features/Anniversaries/ImportantDatesViewModel.swift`：

1. 添加 `private let premiumGate: PremiumGate` 属性和 init 参数
2. 添加观察式状态：

```swift
private(set) var pendingUpsellTrigger: UpsellTrigger?
func dismissUpsell() { pendingUpsellTrigger = nil }
```

3. 拆 `save()`：

```swift
// 旧
func save(_ draft: ImportantDateDraft) async throws {
    // ... 同时处理新建和编辑
}

// 新
func createNew(_ draft: ImportantDateDraft) async throws {
    guard let currentUserID = sessionStore.currentUser?.id else { return }
    
    let ownCount = events.filter { $0.creatorID == currentUserID }.count
    
    if !premiumGate.isPremium && ownCount >= 5 {
        pendingUpsellTrigger = .anniversaryQuota
        return
    }
    
    // ... 原 save() 中的创建逻辑
}

func updateExisting(_ draft: ImportantDateDraft) async throws {
    // ... 原 save() 中的编辑逻辑
}
```

4. 修改 `ImportantDateEditSheet.swift` 调用处：根据 sheet 是 create 模式还是 edit 模式，分别调用 `createNew` 或 `updateExisting`。

- [ ] **Step 4: 运行测试**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/ImportantDatesViewModelQuotaTests 2>&1 | tail -15
```

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Anniversaries/ImportantDatesViewModel.swift Together/Features/Anniversaries/ImportantDateEditSheet.swift Together/App/AppContext.swift TogetherTests/ImportantDatesViewModelQuotaTests.swift
git commit -m "feat(premium): split ImportantDatesViewModel.save into create/update + quota

createNew enforces 5-per-user limit using authored-by model (spec §2.5.1).
Free user at quota: sets pendingUpsellTrigger = .anniversaryQuota.
Partner-authored items don't count against my quota (沾光 mode).
updateExisting bypasses quota (edit is not subject to limit)."
```

---

## Task 19：`ProjectsViewModel` 拆分 + 配额门禁

**目的**：同 Task 18 模式，但阈值为 3。

**Files:**
- Modify: `Together/Features/Projects/ProjectsViewModel.swift`
- Modify: `Together/Features/Projects/ProjectsView.swift`（若需调整调用方）
- Create: `TogetherTests/ProjectsViewModelQuotaTests.swift`

### Step 1: 写失败测试

文件：`TogetherTests/ProjectsViewModelQuotaTests.swift`

```swift
import Testing
import Foundation
@testable import Together

@MainActor
@Suite
struct ProjectsViewModelQuotaTests {
    private let me = UUID()
    private let partner = UUID()

    @Test func freeUnderQuotaAllowsCreate() async throws {
        let (vm, _) = makeViewModel(meCount: 2)
        try await vm.createNew(makeDraft())
        #expect(vm.pendingUpsellTrigger == nil)
        #expect(vm.projects.count == 3)
    }

    @Test func freeAtQuotaBlocksCreate() async throws {
        let (vm, _) = makeViewModel(meCount: 3)
        try await vm.createNew(makeDraft())
        #expect(vm.pendingUpsellTrigger == .projectQuota)
        #expect(vm.projects.count == 3)
    }

    @Test func proBypassesQuota() async throws {
        let (vm, gate) = makeViewModel(meCount: 5)
        gate.overrideStatus = .pro(source: .subscription, expiresAt: nil)
        try await vm.createNew(makeDraft())
        #expect(vm.pendingUpsellTrigger == nil)
        #expect(vm.projects.count == 6)
    }

    @Test func partnerProjectsDontCount() async throws {
        let (vm, _) = makeViewModel(meCount: 2, partnerCount: 100)
        try await vm.createNew(makeDraft())
        #expect(vm.pendingUpsellTrigger == nil)
    }

    // Helpers: makeDraft, makeViewModel, makeExisting — 参照 Task 18 模式，改为 Project / ProjectDraft
    // 略（实现时照搬 Task 18 的 helpers 并替换类型）
}
```

### Step 2: 修改 `ProjectsViewModel`

参照 Task 18 模式：

1. 添加 `premiumGate` 依赖
2. 添加 `pendingUpsellTrigger` / `dismissUpsell()`
3. 拆分 `updateProject()` 为 `createNew()` + `updateExisting()`
4. 在 `createNew` 开头做配额检查：

```swift
func createNew(_ draft: ProjectDraft) async throws {
    guard let currentUserID = sessionStore.currentUser?.id else { return }
    
    let ownCount = projects.filter { $0.creatorID == currentUserID }.count
    
    if !premiumGate.isPremium && ownCount >= 3 {
        pendingUpsellTrigger = .projectQuota
        return
    }
    
    // ... 原 updateProject 中的新建分支
}
```

- [ ] **Step 3: 运行测试**

```bash
xcodebuild test -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TogetherTests/ProjectsViewModelQuotaTests 2>&1 | tail -15
```

- [ ] **Step 4: Commit**

```bash
git add Together/Features/Projects/ProjectsViewModel.swift Together/Features/Projects/ProjectsView.swift Together/App/AppContext.swift TogetherTests/ProjectsViewModelQuotaTests.swift
git commit -m "feat(premium): split ProjectsViewModel.updateProject into create/update + quota

Same pattern as ImportantDatesViewModel: createNew enforces 3-per-user
limit using authored-by model. Partner's projects don't count."
```

---

## Task 20：`ProfileDebugSection` 加 override 控件

**目的**：`#if DEBUG` 下给开发者一个切换会员状态的 UI，方便模拟器测试。

**Files:**
- Modify: `Together/Features/Profile/ProfileDebugSection.swift`

### Step 1: 看现状

```bash
cat Together/Features/Profile/ProfileDebugSection.swift | head -40
```

### Step 2: 追加 Debug 控件

在 `ProfileDebugSection` 的现有 Form 或 Section 结构里追加一个新 section：

```swift
#if DEBUG
Section("会员状态 Override (仅 DEBUG)") {
    Picker("Override", selection: $overrideSelection) {
        Text("不覆盖（真实状态）").tag(0)
        Text("Free").tag(1)
        Text("Pro (Subscription)").tag(2)
        Text("Pro (Grant)").tag(3)
        Text("Grace (7 天剩)").tag(4)
        Text("Grace (1 天剩)").tag(5)
    }
    .onChange(of: overrideSelection) { _, newValue in
        applyOverride(newValue)
    }
    
    Button("立即 Refresh") {
        Task { await appContext.container.premiumGate.refresh() }
    }
}
#endif
```

并添加 state 与 apply 函数：

```swift
@State private var overrideSelection: Int = 0

private func applyOverride(_ tag: Int) {
    let gate = appContext.container.premiumGate
    switch tag {
    case 0: gate.overrideStatus = nil
    case 1: gate.overrideStatus = .free
    case 2: gate.overrideStatus = .pro(
        source: .subscription,
        expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())
    )
    case 3: gate.overrideStatus = .pro(source: .grant, expiresAt: nil)
    case 4:
        let expiry = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        gate.overrideStatus = .gracePeriod(
            originalExpiry: expiry,
            logbookFullUntil: expiry.addingTimeInterval(14 * 86400)
        )
    case 5:
        let expiry = Calendar.current.date(byAdding: .day, value: -13, to: Date())!
        gate.overrideStatus = .gracePeriod(
            originalExpiry: expiry,
            logbookFullUntil: expiry.addingTimeInterval(14 * 86400)
        )
    default: break
    }
}
```

（`appContext` 依 `ProfileDebugSection` 现有注入方式访问；通常是 `@EnvironmentObject` 或 `@Environment` 形式）

- [ ] **Step 3: Build 验证**

```bash
xcodebuild build -scheme Together -destination 'platform=iOS Simulator,name=iPhone 15' 2>&1 | tail -5
```

- [ ] **Step 4: 模拟器手动验证**

1. 启动 Debug build
2. 进入 Profile → Debug 区域
3. 切换 Override 到"Free"，观察纪念日超 5 个时是否触发 upsell sheet
4. 切换到"Pro (Subscription)"，观察超 5 个可继续创建
5. 切换到"Grace"，观察 Logbook 可全历史

- [ ] **Step 5: Commit**

```bash
git add Together/Features/Profile/ProfileDebugSection.swift
git commit -m "feat(debug): add premium status override picker to ProfileDebugSection

DEBUG-only UI to manually toggle PremiumGate.overrideStatus across
free / pro(sub) / pro(grant) / grace(7d) / grace(1d). Enables fast
manual verification of all gate points without real StoreKit flow."
```

---

## Task 21：端到端 Smoke Test Checklist

**目的**：手动确认整个 Phase 2 系统工作。非代码 task，就是一份验收清单。

**Files:**
- 无（只是验证步骤）

### Step 1: 准备测试账号

- [ ] 在 Supabase Dashboard → `auth.users` 确认你自己的 user_id
- [ ] 在 Supabase SQL Editor 执行：

```sql
INSERT INTO premium_grants (user_id, category, reason, granted_by)
VALUES ('<你的 user_id>', 'developer', 'Dogfood', 'manual-setup');
```

### Step 2: Debug Build Smoke Test（不依赖真实 RevenueCat）

全部走 `ProfileDebugSection` 的 override：

- [ ] 启动 App，登录
- [ ] Profile → Debug → Override = "Free"
- [ ] Anniversaries：创建到第 5 个成功；创建第 6 个应触发 upsell sheet（本 Phase 尚无真实付费墙，预期弹一个占位 sheet 或 console log）
- [ ] Projects：创建到第 3 个成功；第 4 个触发 upsell
- [ ] Logbook：滚动到 30 天前，应看到数据截断
- [ ] 模拟器安装到第二台虚拟设备，登同一账号：不会启动 CKSyncEngine（观察日志）
- [ ] Override = "Pro (Subscription)"
- [ ] 以上限制全部消失

### Step 3: 真实 Grant Smoke Test

- [ ] Override = "不覆盖"
- [ ] 冷启动 App（重启模拟器）
- [ ] 观察 `PremiumGate.status` 应为 `.pro(source: .grant, expiresAt: nil)`（因为 Supabase 表里有你的 grant）
- [ ] `isPremium == true`

### Step 4: 撤销 Grant 验证

- [ ] Supabase SQL Editor 运行：
  ```sql
  UPDATE premium_grants SET revoked_at = now() WHERE user_id = '<你的 user_id>';
  ```
- [ ] App 里下拉刷新 Profile / 或等 scene activation 触发 refresh
- [ ] 观察 `status` 变为 `.free`
- [ ] 所有配额重新生效

### Step 5: 缓存离线验证

- [ ] 确认 grant 有效（insert 一条）
- [ ] Bootstrap 一次，缓存生效
- [ ] 开启模拟器"Airplane Mode"或断网
- [ ] 杀掉 App 重启
- [ ] 观察冷启动时 gate 仍能从缓存恢复 `.pro` 状态，App 可用 Pro 功能

### Step 6: 签出 Checklist 完成

所有上述条目 ✅ 后，Phase 2 验收通过，可进入 Track D1（RevenueCat 生产 key 配置）+ Phase 3（付费墙 UI）流程。

- [ ] **Step 7: Tag 一个里程碑**

```bash
git tag -a phase-2-infrastructure -m "Phase 2 Premium Infrastructure complete

- PremiumGate with source-agnostic merge + bootstrap race protection
- premium_grants table + RLS + CLI migrations
- RevenueCat SDK wired (public key placeholder)
- 4 module gates: sync / anniversaries / projects / logbook
- ProfileDebugSection override picker
- End-to-end smoke tests passing"
```

---

## Self-Review

### Spec 覆盖 Check（对应 Phase 2 spec 的 12 节）

| Spec 节 | 覆盖任务 |
|---|---|
| § 1 架构总览 | 贯穿全体 |
| § 2 PremiumGate | Tasks 1, 2, 3, 4, 5, 6, 7 |
| § 2.3 合并规则 | Task 6（11 个测试覆盖完整） |
| § 2.4 竞态防护 | Task 7（`staleBootstrapResultIsDiscarded`） |
| § 2.5 Debug override | Tasks 7 (property) + 20 (UI) |
| § 3 Supabase 后端 | Task 8 |
| § 4 RevenueCat 接入 | Tasks 9, 10, 11 |
| § 5 模块门禁 | Tasks 15, 16, 17, 18, 19 |
| § 5.2 UpsellTrigger | Task 2 |
| § 5.6 SyncEngineCoordinator | Task 15 |
| § 6 错误 / 离线 | Tasks 3, 4 |
| § 7 身份同步 | Task 14 |
| § 8 测试策略 | 全体 TDD + Task 21 |
| § 9 文件清单 | 全体 |

### Placeholder Scan

- ✅ 无 `TBD` / `TODO` 产品决策留白
- ✅ `appl_REPLACE_WITH_REAL_KEY`（Task 10）是运行时替换值，不是 spec 空白
- ✅ `<timestamp>` 在 migration 文件名是约定占位，Task 8 已给出具体值
- ✅ `<你的 user_id>` 在 Task 21 是用户手动替换值

### Type Consistency Check

- `PremiumStatus`（Task 1）与 Task 7 中 `overrideStatus` 类型一致 ✓
- `UpsellTrigger.anniversaryQuota`（Task 2）与 Task 18 中 `pendingUpsellTrigger = .anniversaryQuota` 一致 ✓
- `RCEntitlementSnapshot`（Task 5）字段 `isProActive` / `proExpirationDate` 在 Task 6 合并规则和 Task 11 实现中引用一致 ✓
- `PremiumGrant.Category`（Task 5）4 个 case 与 Supabase CHECK 约束（Task 8）一致 ✓
- `GatedFeature`（Task 3）与 `PremiumGateError.quotaExceeded(limit:, feature:)`（Task 3）引用一致 ✓
- `ItemRepository.fetchCompletedItems(... since: ...)`（Task 16）与 `CompletedHistoryViewModel`（Task 17）调用一致 ✓

### Known Minor Deviations from Spec

- **测试文件扁平放置**（不放 `TogetherTests/Premium/` 子目录），对齐项目现有惯例，spec § 9 里的子目录路径作为建议，实际落地遵循项目风格
- Task 20 的 Override picker **UI 文案**是 plan 作者自拟（spec § 2.5 只列了 6 个 case 名称），实现时可按视觉需要调整

---

## 执行完成标志

- [ ] Tasks 1-20 全部 commit，各自测试通过
- [ ] Task 21 smoke test 全部 ✅
- [ ] `phase-2-infrastructure` tag 打好
- [ ] 代码 push 到 origin/main
- [ ] **下一步**：进入 **Track B1 Phase 3 付费墙 UI brainstorming**（由 Roadmap 指引，另外启动 brainstorming skill）
