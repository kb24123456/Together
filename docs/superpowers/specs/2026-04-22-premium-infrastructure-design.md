# Premium Infrastructure — Phase 2 Technical Design Spec

- **Date**: 2026-04-22
- **Status**: Draft (pending written-spec review)
- **Scope**: Phase 2 技术实现设计 —— RevenueCat + Supabase + 客户端 `PremiumGate` + 各模块门禁改造
- **Upstream spec**: `docs/superpowers/specs/2026-04-22-premium-tier-split-design.md` (Final)
- **Roadmap**: `docs/superpowers/plans/2026-04-22-premium-rollout-roadmap.md`
- **Follow-up specs**:
  - *Pricing Strategy* (月 / 年 / 终身价格 + 试用) — 独立 spec
  - *Paywall UI & Compliance* (Phase 3) — 依赖本 spec 产出的 `PremiumGate` API 与 `UpsellTrigger` 模型

## Goal

产出一份技术设计规范，让 Phase 2 的 writing-plans 能直接据此写出代码级 TDD 计划。覆盖：

- 订阅验证路线与 SDK 选择
- 后端 `premium_grants` 表结构与安全策略
- 客户端 `PremiumGate` 架构（API 形态、合并逻辑、状态机、离线缓存）
- 身份同步（RC `appUserID` ↔ Supabase `auth.users.id`）
- 各业务模块的门禁改造位置与改造方式
- 测试策略与 Mock 模型

## Non-Goals

- 不定义代码实现（留给 writing-plans + 实现阶段）
- 不定义订阅价格数字（留给独立 Pricing spec）
- 不定义付费墙 UI（Phase 3）
- 不包含 Edge Function（MVP 阶段不建）
- 不处理 Apple Server Notifications v2 自托管（业界轮子已足够）
- 不处理家庭共享（产品 spec 已定 1.0 不做）
- 不处理 Android / Web 跨平台（1.0 仅 iOS）

## § 1. 架构总览

```
┌──────────────────────────────────────────────────────────┐
│  iOS Client (Together)                                    │
│                                                           │
│  ┌─────────────┐     ┌────────────┐                       │
│  │SessionStore │────→│PremiumGate │← @Observable 注入      │
│  │  (existing) │     │  (new)     │    到 ViewModels       │
│  └─────────────┘     └─────┬──────┘                       │
│         │                   │                              │
│         │                   ├──→ RC SDK ──→ RevenueCat Cloud│
│         │                   └──→ Supabase ─→ premium_grants │
│         └────── Auth ───────┘                              │
└──────────────────────────────────────────────────────────┘
                             │
        ┌────────────────────┴────────────────────┐
        ▼                                          ▼
  RevenueCat Cloud (US)                    Supabase Cloud
  - StoreKit 收据验证                       - premium_grants 表
  - Entitlement `pro` 状态                   - RLS: 只能读自己
  - appUserID = Supabase user_id             - 写操作仅 service_role
```

**核心路线**：**RevenueCat SDK + Supabase `premium_grants` 表 + 客户端合并**（不建 Edge Function）。

**关键对齐**：RC `appUserID` = Supabase `auth.users.id`，两边天然对齐，无需额外映射表。

## § 2. `PremiumGate` — 客户端会员门禁核心

### 2.1 位置与类签名

新建目录 `Together/Services/Premium/`，核心文件：

```
Together/Services/Premium/
├── PremiumGate.swift              (核心 @Observable 类)
├── PremiumStatus.swift            (enum + 计算辅助)
├── UpsellTrigger.swift            (ViewModel → View 升级信号)
├── PremiumStatusCache.swift       (UserDefaults 包装)
├── RevenueCatConfig.swift         (常量 + API key 持有)
├── RCClientProtocol.swift         (RC 访问抽象，便于测试)
└── GrantsLoader.swift             (Supabase premium_grants 查询，含 Protocol)
```

**类签名**：

```swift
@MainActor
@Observable
final class PremiumGate {
    // MARK: - Public read
    private(set) var status: PremiumStatus = .unknown
    var isPremium: Bool { status.isPremium }
    var allowsFullLogbook: Bool { status.allowsFullLogbook }

    // MARK: - Lifecycle
    func bootstrap(userID: UUID) async
    func refresh() async
    func logOut()

    // MARK: - Debug override
    #if DEBUG
    var overrideStatus: PremiumStatus?
    #endif

    // MARK: - Init / DI
    init(
        rcClient: RCClientProtocol,
        grantsLoader: GrantsLoaderProtocol,
        cache: PremiumStatusCache,
        clock: Clock
    )
}
```

所有外部依赖（RC、Supabase 查询、缓存、时钟）走 protocol 注入，便于单元测试。`PremiumGate` 本身不抽 protocol（保持与 `SessionStore` 一致），测试通过依赖注入 + `#if DEBUG overrideStatus` 两手段组合实现。

### 2.2 `PremiumStatus` 枚举

```swift
enum PremiumStatus: Equatable {
    case unknown                                       // 尚未 bootstrap
    case free
    case pro(source: PremiumSource, expiresAt: Date?)  // expiresAt=nil 即永久
    case gracePeriod(originalExpiry: Date, logbookFullUntil: Date)

    enum PremiumSource: String {
        case subscription       // RC 订阅
        case grant              // premium_grants 白名单
    }

    var isPremium: Bool {
        switch self {
        case .pro, .gracePeriod: return true
        case .unknown, .free: return false
        }
    }

    var allowsFullLogbook: Bool { isPremium }   // Pro 或 Grace 期内都允许
}
```

### 2.3 合并规则（源无关的 Grace Period 判定）

**关键设计**：grace period 判定**与来源无关**，任何一个来源曾经有效并在过去 14 天内失效，都进入 grace period。这样 TestFlight grant 到期（类别 ④）也能正确走宽限期。

```
INPUT:
  rcResult: Result<RCCustomerInfo, Error>
  grantsResult: Result<[PremiumGrant], Error>
  cachedStatus: PremiumStatus?

ALGORITHM:
  step 1: 收集所有"Pro 生效期"记录
    sources: [(source: PremiumSource, startedAt: Date?, expiresAt: Date?)]
    - 若 rcResult.success 且 entitlement["pro"].isActive
      → append (subscription, 开始时间, entitlement.expirationDate or nil)
    - 若 grantsResult.success
      → for each active grant (revoked_at IS NULL):
         append (grant, granted_at, expires_at or nil)

  step 2: 当前是否有任一有效来源？
    活跃 = sources 中存在 (expiresAt == nil OR expiresAt > now)
    → .pro(source: pickBest(sources), expiresAt: 取最大有效期)

  step 3: 任一来源在过去 14 天内失效？
    近期过期 = sources 中 expiresAt != nil AND now - 14d < expiresAt <= now
    → .gracePeriod(
          originalExpiry: 近期过期集合中的最大 expiresAt (最晚过期的那个),
          logbookFullUntil: originalExpiry + 14 days
       )

  step 4: 两查询都失败且缓存有效
    → cachedStatus

  step 5: fall through
    → .free

pickBest 优先级: 
  - 先选 expiresAt=nil (永久) 的
  - 再选 expiresAt 最晚的
  - 多个同样永久时优先 .subscription（反映用户真实付费意愿）
```

### 2.4 Bootstrap 竞态防护

快速登录/登出/再登录场景下，多次 bootstrap 可能乱序完成并覆盖彼此。防御策略：

```
func bootstrap(userID: UUID) async {
    let token = UUID()
    bootstrapToken = token
    
    let rcResult = ...
    let grantsResult = ...
    
    // 只有 token 仍是最新的才应用结果
    guard bootstrapToken == token else { return }
    
    status = computeStatus(rcResult, grantsResult, cache.load())
    cache.save(status)
}
```

同一机制应用于 `refresh()`。

### 2.5 Debug Override 与 ProfileDebugSection 联动

`ProfileDebugSection`（现有 `Together/Features/Profile/ProfileDebugSection.swift`）新增控件：

```
[覆盖会员状态]
 ○ 不覆盖
 ○ Free
 ○ Pro (subscription)
 ○ Pro (grant)
 ○ Grace Period (7 天内)
 ○ Grace Period (14 天即将结束)
```

UI 选中后设置 `premiumGate.overrideStatus`。`status` 的 getter 读取时，若 override 存在则返回 override，否则返回真实计算结果。

## § 3. Supabase 后端

### 3.1 `premium_grants` 表

```sql
-- File: supabase/migrations/<timestamp>_premium_grants.sql

CREATE TABLE premium_grants (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category    text NOT NULL CHECK (category IN ('developer', 'friend', 'grandfather', 'testflight')),
    reason      text,
    granted_at  timestamptz NOT NULL DEFAULT now(),
    expires_at  timestamptz,                -- NULL = 永久
    revoked_at  timestamptz,                -- 软删除
    granted_by  text,                       -- 操作人邮箱 / 'system' / 'migration-script'
    metadata    jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX idx_premium_grants_user_id ON premium_grants(user_id);
CREATE INDEX idx_premium_grants_active 
    ON premium_grants(user_id, expires_at) 
    WHERE revoked_at IS NULL;
```

**字段说明**：

| 字段 | 用途 |
|---|---|
| `category` | 分类：developer / friend / grandfather / testflight（受 CHECK 约束） |
| `reason` | 自由文本备注，如 "创始团队"、"七夕 2026 答谢"，运营审计用 |
| `granted_by` | 谁做的这次 insert（邮箱或 "migration-script"），审计用 |
| `metadata` | 预留扩展字段，MVP 为空 |

### 3.2 Row-Level Security 策略

```sql
ALTER TABLE premium_grants ENABLE ROW LEVEL SECURITY;

-- SELECT: 用户只能查看自己的记录
CREATE POLICY "users_read_own_grants"
    ON premium_grants FOR SELECT
    USING (auth.uid() = user_id);

-- INSERT/UPDATE/DELETE 默认无 policy，即 authenticated 用户无法写入
-- 仅 service_role 能写入（Supabase Dashboard SQL Editor、管理脚本、CLI）
```

### 3.3 多条 Grants 支持

同一 user_id 允许多条 grants（如同时是 grandfather + testflight），合并逻辑见 § 2.3 的 `pickBest`。**不设 UNIQUE(user_id) 约束**，保留审计轨迹。

### 3.4 项目目录与迁移工作流

```
supabase/                         (新建)
├── config.toml                   (运行 `supabase init` 生成)
└── migrations/
    └── <timestamp>_premium_grants.sql
```

**两种工作流都接受**：

1. **Supabase CLI（推荐长期）** — 开发机安装 `supabase` CLI，本地 migrations 目录 + `supabase db push` 同步到云端。未来新 migrations 也走这里。
2. **Dashboard 手工粘 SQL（MVP 可接受）** — 直接在 Supabase Dashboard SQL Editor 跑迁移 SQL。但 SQL 文件仍要 commit 到仓库作为单一真相源。

### 3.5 Grant 撤销流程

撤销某个 grant：

```sql
UPDATE premium_grants SET revoked_at = now() WHERE id = '<grant-uuid>';
```

客户端查询时隐式加 `WHERE revoked_at IS NULL`，撤销后下次 refresh 自动失效。数据物理保留便于审计。

## § 4. RevenueCat 接入

### 4.1 SDK 添加

通过 Swift Package Manager：

```
Xcode → File → Add Package Dependencies
URL: https://github.com/RevenueCat/purchases-ios
Version: latest stable 5.x
```

`Package.resolved` 纳入 git。

### 4.2 配置常量

```swift
// File: Together/Services/Premium/RevenueCatConfig.swift

enum RevenueCatConfig {
    static let publicSDKKey: String = "<RC public SDK key>"     // 从 RC Dashboard 获取
    static let entitlementIdentifier: String = "pro"             // 与 RC Dashboard 约定
}
```

API key 的管理策略：

- **公开 SDK key** 可直接硬编码（RC 设计上如此，类似 Supabase anon key）
- 正式上线前替换为 production key（RC Dashboard 区分 sandbox/production）

### 4.3 初始化时机与生命周期

**延后 configure**：仅在用户登录后 configure RC SDK。未登录状态不初始化，因付费墙必须登录后才触达。

修改 `Together/App/AppContext.swift`：

```swift
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

        await premiumGate.bootstrap(userID: user.id)
    }
}
```

触发点：

| 触发时机 | 代码位置 | 说明 |
|---|---|---|
| 冷启动且已登录 | `AppContext.postLaunchWorkIfNeeded()` | 启动时一次 |
| 登录完成 | `SessionStore.handleSignIn()` 后 | 切换用户 |
| App 回到前台 | `ScenePhase → .active` 观察者 | 条件刷新：距上次 > 1 小时才 refresh |
| 手动下拉刷新（Profile） | Profile 页面 | 用户主动信号 |
| 付费墙展示前 | Phase 3 付费墙 View | 保证价格和状态最新 |

**不做**：定时轮询刷新（电池杀手，无必要）。

### 4.4 登出清理

```swift
extension AppContext {
    func teardownPremiumGate() async {
        premiumGate.logOut()                           // 清空状态 + 清 UserDefaults 缓存
        _ = try? await Purchases.shared.logOut()        // RC SDK 原生支持
    }
}
```

在 `SessionStore.clearForSignOut()` 内或之后调用。

### 4.5 换设备行为

RC 以 `appUserID` = Supabase `auth.users.id` 为识别键。用户在 iPhone A 订阅、换到 iPhone B 登录同一 Supabase 账号：

- RC 识别同一 appUserID → 自动带 `pro` entitlement → 客户端 `isPremium = true`
- Supabase `premium_grants` 按 user_id 查询 → 自动带出白名单权益

**换设备流程自动正确**，无需额外代码。

## § 5. 各业务模块的门禁改造

### 5.1 改造总览

| 模块 | 触发行为 | 阻止方式 | 源产品 spec |
|---|---|---|---|
| 本人跨设备同步 | App 启动时 `startSoloSync()` | 非 Pro 直接 early-return，不启动 CKSyncEngine | § 2 Pro 功能 1 |
| 纪念日配额 | 用户新建纪念日 | ViewModel 设置 `pendingUpsellTrigger = .anniversaryQuota`，View 展示付费墙 | § 2 Pro 功能 2 |
| 项目配额 | 用户新建项目 | 同上，trigger 为 `.projectQuota` | § 2 Pro 功能 3 |
| Logbook 历史 | 加载 completed items 时 | 非 Pro 限制 `since = now - 30d` 过滤 | § 2 Pro 功能 4 |

### 5.2 ViewModel → View 的升级信号：`UpsellTrigger` 模型

**不走 Error 通道**，改走 `@Observable` 属性通道，与全项目一致：

```swift
// File: Together/Services/Premium/UpsellTrigger.swift

enum UpsellTrigger: Identifiable, Equatable {
    case anniversaryQuota
    case projectQuota
    case logbookHistory
    case crossDeviceSync

    var id: String {
        switch self {
        case .anniversaryQuota: "anniversary_quota"
        case .projectQuota: "project_quota"
        case .logbookHistory: "logbook_history"
        case .crossDeviceSync: "cross_device_sync"
        }
    }
}
```

每个受影响的 ViewModel 暴露：

```swift
private(set) var pendingUpsellTrigger: UpsellTrigger?
func dismissUpsell() { pendingUpsellTrigger = nil }
```

View 观察：

```swift
.sheet(item: $viewModel.pendingUpsellTrigger) { trigger in
    PaywallView(trigger: trigger, onDismiss: viewModel.dismissUpsell)
}
```

Phase 3 付费墙 spec 直接接 `UpsellTrigger`，与 Phase 2 解耦。

### 5.3 纪念日配额 —— `ImportantDatesViewModel` 改造

**现状**：`save()` 方法在 L35 同时处理新建和编辑，无法区分。

**改造方式**：**方法拆分**（清晰度最高）。

```
File: Together/Features/Anniversaries/ImportantDatesViewModel.swift

改造点：
  - 旧: func save(_ draft: ImportantDateDraft) async throws
  - 新: 
      func createNew(_ draft: ImportantDateDraft) async
      func updateExisting(_ draft: ImportantDateDraft) async throws

改造 UI 调用处：
  - ImportantDateEditSheet 根据是否是编辑模式分别调用
```

`createNew` 内部的门禁检查：

```
func createNew(_ draft: ImportantDateDraft) async {
    guard let currentUserID = sessionStore.currentUser?.id else { return }

    let ownCount = events.filter { 
        $0.creatorID == currentUserID 
    }.count

    if !premiumGate.isPremium && ownCount >= 5 {
        pendingUpsellTrigger = .anniversaryQuota
        return
    }

    // ... 原有创建逻辑
}
```

**注意**：`events` 是当前选中 workspace 的纪念日列表（solo 或 pair 空间）。配额判定是"**当前空间中 `creatorID == 本人` 的数量**"，对应产品 spec § 2.5.1 authored-by 模型。

### 5.4 项目配额 —— `ProjectsViewModel` 改造

**现状**：`updateProject()` 方法在 L152 同时处理新建和编辑。

**改造方式**：同样拆分为 `createNew(_:)` 和 `updateExisting(_:)`。门禁逻辑：

```
func createNew(_ draft: ProjectDraft) async {
    guard let currentUserID = sessionStore.currentUser?.id else { return }

    let ownCount = projects.filter { 
        $0.creatorID == currentUserID 
    }.count

    if !premiumGate.isPremium && ownCount >= 3 {
        pendingUpsellTrigger = .projectQuota
        return
    }

    // ... 原有创建逻辑
}
```

### 5.5 Logbook 30 天过滤 —— `CompletedHistoryViewModel` + Repository 改造

**Repository 层加 `since:` 参数**：

```
File: Together/Services/Items/ItemRepository.swift (以及 LocalItemRepository / SupabaseSyncService 对应实现)

改造点：
  - 旧: func fetchCompletedItems(
          spaceID: UUID, searchText: String?, before: Date?, limit: Int
        ) async throws -> [Item]
  - 新: func fetchCompletedItems(
          spaceID: UUID, searchText: String?, before: Date?, 
          since: Date? = nil,                                    // ← 新参数
          limit: Int
        ) async throws -> [Item]
```

SQL/Predicate 层叠加：`completedAt >= since`（若 since != nil）。

**ViewModel 层**：

```
File: Together/Features/Profile/CompletedHistoryViewModel.swift

改造 fetchPage(...) 调用处：

  let since: Date? = premiumGate.allowsFullLogbook
      ? nil
      : Calendar.current.date(byAdding: .day, value: -30, to: .now)

  let items = try await itemRepository.fetchCompletedItems(
      spaceID: spaceID,
      searchText: searchText,
      before: before,
      since: since,                  // ← 新传入
      limit: pageSize
  )
```

列表底部："升级查看全部历史 >" 卡片的展示逻辑：
- 非 Pro 且已加载到 30 天边界时显示
- 用户点击 → ViewModel 设置 `pendingUpsellTrigger = .logbookHistory`
- 点击展示 Phase 3 付费墙

### 5.6 本人跨设备同步 —— `SyncEngineCoordinator` 改造

**现状**：`Together/Sync/Engine/SyncEngineCoordinator.swift:60` 的 `startSoloSync()` 无任何 guard。

**改造方式**：方法开头加早返回。

```
File: Together/Sync/Engine/SyncEngineCoordinator.swift

改造点 L60:
  func startSoloSync() {
      guard premiumGate.isPremium else { return }   // ← 新增
      guard !isRunningSolo else { return }           // 原有
      // ... 原有启动逻辑
  }
```

**不抛错**：静默不启动。升级 CTA 由产品 spec § 3 第 4 行的"新设备首次打开且本机无数据"触发点负责，不走这条代码路径。

## § 6. 错误处理与离线行为

### 6.1 `PremiumGateError`（仅配额相关）

```swift
enum PremiumGateError: Error, Equatable {
    case quotaExceeded(limit: Int, feature: GatedFeature)
}

enum GatedFeature {
    case anniversary
    case project
    case logbookHistory
}
```

**不包含 `.syncNotAvailable`**：跨设备同步由 UI 层"新设备首次打开"触发升级引导，不走 Error 通道。

（实际上本 spec 设计下 `PremiumGateError` 几乎不抛 —— ViewModel 走 `UpsellTrigger` 通道。`PremiumGateError` 保留做为某些辅助场景的明确信号类型，例如未来批量导入时返回失败原因。MVP 可选保留或精简为仅含 `.quotaExceeded`。）

### 6.2 离线缓存 `PremiumStatusCache`

```swift
// File: Together/Services/Premium/PremiumStatusCache.swift

final class PremiumStatusCache {
    private let defaults: UserDefaults
    private let cacheKey = "premium.cachedStatus.v1"
    private let timestampKey = "premium.cachedStatusTimestamp.v1"
    private let ttl: TimeInterval = 7 * 24 * 3600  // 7 天
    private let clock: Clock

    init(defaults: UserDefaults = .standard, clock: Clock)

    func load() -> PremiumStatus?         // 返回缓存，若过期则返回 nil
    func save(_ status: PremiumStatus)    // 持久化 + 写时间戳
    func clear()                          // 登出时调用
}
```

序列化：`PremiumStatus` 自身通过 `Codable` 编码（需要给 enum 加 `Codable`）。

### 6.3 查询失败的回退策略

对应产品原则：**离线不误伤已付费用户**。合并规则的 step 4（见 § 2.3）：

- RC 查询失败 **或** Supabase 查询失败，**且**缓存有效（未过 7 天）→ 返回缓存
- 两者都失败**且**缓存也不存在 → 返回 `.free`
- 任一成功 → 走正常合并逻辑（不依赖缓存）

此策略让已订阅用户离线仍能用 Pro 功能（至少 7 天缓存期内）。

### 6.4 刷新入口总结

用户直接暴露的刷新入口：**无**。

- 付费墙带"恢复购买"按钮（Apple 合规要求，Phase 3 付费墙 spec 处理），间接触发 `refresh()`
- 不在 Profile 加独立"刷新会员"按钮（用户不理解必要性，降低复杂度）

## § 7. 身份同步 —— RC `appUserID` = Supabase `auth.users.id`

### 7.1 配置规则

```
Purchases.configure(withAPIKey: ..., appUserID: user.id.uuidString)
```

`user.id` 来自 `SessionStore.currentUser!.id`（类型 `UUID`）。转 String 作为 RC 的 appUserID。

### 7.2 切换账号

```
await Purchases.shared.logIn(newUserID.uuidString)
```

RC SDK 会处理 appUserID 切换 + 重新拉取 entitlements。

### 7.3 登出

```
try? await Purchases.shared.logOut()
```

RC 切回匿名态。紧接着 `PremiumGate.logOut()` 清空状态。

## § 8. 测试策略

### 8.1 单元测试

| 文件 | 测试对象 | 覆盖的案例 |
|---|---|---|
| `TogetherTests/Premium/PremiumGateTests.swift` | `PremiumGate.computeStatus` | 各种组合：仅 RC / 仅 grant / 两个都有效 / 两个都过期 / RC 过期且在 grace 内 / grant 过期且在 grace 内 / 两个都过期在 grace 外 / 查询失败 + 缓存命中 / 查询失败 + 无缓存 |
| 同上 | `PremiumGate.bootstrap` 竞态 | 快速两次 bootstrap，后者结果胜出 |
| `TogetherTests/Premium/PremiumStatusCacheTests.swift` | `PremiumStatusCache` | TTL 有效 / TTL 过期 / 持久化与读取一致 / clear 行为 |
| `TogetherTests/Features/Anniversaries/ImportantDatesViewModelTests.swift` | `createNew` | Free 且已有 5 个本人 → `pendingUpsellTrigger = .anniversaryQuota` / Pro → 正常创建 / Free 但已有 5 个对方创建的 → 仍允许（沾光模式） |
| `TogetherTests/Features/Projects/ProjectsViewModelTests.swift` | `createNew` | 同上逻辑，阈值 3 |
| `TogetherTests/Features/Profile/CompletedHistoryViewModelTests.swift` | `fetchPage` | Free → Repository 调用带 `since=30daysAgo` / Pro → since=nil / Grace → since=nil |
| `TogetherTests/Sync/SyncEngineCoordinatorTests.swift` | `startSoloSync` | Free → 不启动 / Pro → 启动 |

### 8.2 Mock 策略

`PremiumGate` 内部依赖走 protocol 注入：

- `RCClientProtocol` — 封装 `Purchases.shared.customerInfo()` 等调用
- `GrantsLoaderProtocol` — 封装 Supabase 查询

测试用 stub 实现，能控制返回结果（成功/失败/特定数据）。

ViewModel 测试用 PremiumGate 具体类，通过 `overrideStatus` 控制（需要加一个 `internal` 的 override setter）。

### 8.3 模拟器手动测试

- **StoreKit Configuration File**：Xcode 内建，添加 `Products.storekit`，在模拟器跑沙盒订阅 / trial / 取消流程，不依赖真机
- **ProfileDebugSection 的 Override**：在模拟器 / TestFlight Debug 构建下直接切换会员状态，观察各 ViewModel / View 响应

## § 9. 文件清单

### 9.1 新建文件（10 个）

```
Together/Services/Premium/
├── PremiumGate.swift
├── PremiumStatus.swift
├── UpsellTrigger.swift
├── PremiumStatusCache.swift
├── PremiumGateError.swift
├── RevenueCatConfig.swift
├── RCClientProtocol.swift
└── GrantsLoader.swift

supabase/
├── config.toml                     (`supabase init` 生成)
└── migrations/
    └── <timestamp>_premium_grants.sql
```

测试：

```
TogetherTests/Premium/
├── PremiumGateTests.swift
├── PremiumStatusCacheTests.swift
└── UpsellTriggerTests.swift (若有独立逻辑)
```

### 9.2 修改文件（7 个）

```
Together/App/AppContext.swift                    — 添加 PremiumGate 注入 + 生命周期挂钩
Together/App/AppContainer.swift                  — PremiumGate 单例 + 依赖组装
Together/Sync/Engine/SyncEngineCoordinator.swift — L60 加 isPremium guard
Together/Features/Anniversaries/ImportantDatesViewModel.swift — save() 拆为 createNew/updateExisting + 门禁
Together/Features/Projects/ProjectsViewModel.swift — updateProject() 拆分 + 门禁
Together/Features/Profile/CompletedHistoryViewModel.swift — 注入 PremiumGate + since 参数
Together/Features/Profile/ProfileDebugSection.swift — 添加会员状态 override 控件（DEBUG only）
```

Repository 层：

```
Together/Services/Items/ItemRepository.swift           — fetchCompletedItems 加 since: 参数
Together/Services/Items/LocalItemRepository.swift      — 对应实现
Together/Sync/SupabaseSyncService.swift                — 对应实现
Together/Services/Items/MockItemRepository.swift       — 对应实现
```

总计：新建 10-11 文件，修改 11 文件。

## § 10. 依赖与环境

### 10.1 新增依赖

- `purchases-ios` (RevenueCat Swift Package) 5.x

### 10.2 环境凭据

| 凭据 | 存放位置 | 说明 |
|---|---|---|
| RC Public SDK Key | `RevenueCatConfig.swift` 常量 | RC Dashboard 生成，可硬编码 |
| Supabase URL / Anon Key | 已在 `SupabaseClient.swift` 硬编码（现状）| 保持不变 |
| RC Secret API Key | **不需要** | 本架构客户端不调用 RC Server API |

## § 11. 决策溯源

本 spec 的技术决策对应 brainstorming 对话（2026-04-22）：

1. **路线选择**：RevenueCat SDK + Supabase `premium_grants` + 客户端合并（问题 3 · 方案 B）
2. **PremiumGate 形态**：`@Observable` 具体类 + DEBUG override（问题 2a · B）
3. **API 最小集**：bootstrap / refresh / status 三件套（问题 2b · A）
4. **Grace Period 判定**：客户端算，**源无关**（问题 2c · A + 复核问题 1 修复）
5. **表结构与 RLS**：`premium_grants` schema + 只读自己 RLS（问题 4a/4c · A）
6. **多条 Grants 允许**：保留审计轨迹（问题 4b · A）
7. **软删除**：`revoked_at`（问题 4d · A）
8. **身份同步**：RC `appUserID` = Supabase `user.id.uuidString`（问题 5）
9. **延后 configure**：登录后才 init RC（问题 5a · A）
10. **登出时 logOut RC**：清理干净（问题 5b · A）
11. **刷新节奏**：启动 + 付费墙前 + 场景激活时条件刷新 + 不定时轮询（问题 6a · A）
12. **离线缓存**：UserDefaults + 7 天 TTL（问题 6b · A）
13. **失败回退**：用缓存，保护已付费用户（问题 6c · A）
14. **无手动刷新按钮**：恢复购买 + 付费墙前刷新已覆盖（问题 6d · C）

### 复核阶段补齐（7 项）

15. **Grace Period 源无关**：RC / grant 任一源近期过期都进 grace（复核问题 1）
16. **`save()` 拆分**：拆为 `createNew` / `updateExisting`（复核问题 2）
17. **`since:` 参数**：Repository `fetchCompletedItems` 加新参数（复核问题 3）
18. **`UpsellTrigger` 模型**：ViewModel → View 走 `@Observable` 属性（复核问题 4）
19. **Bootstrap 竞态防护**：token 标记（复核问题 5）
20. **Supabase 工作流**：CLI 优先 + Dashboard 可接受（复核问题 6）
21. **删除 `.syncNotAvailable`**：同步走静默不启动（复核问题 7）

## § 12. 下一步

本 spec 批准后：

1. 进入 `superpowers-writing-plans` 流程，产出代码级 TDD plan
2. writing-plans 会为每个新建/修改文件定义：
   - 测试先行（TDD 红 → 绿 → 重构）
   - 每个 commit 的 boundary
   - Xcode build 验证步骤
3. 实现阶段推荐使用 `superpowers-subagent-driven-development`（独立 subagent per task + 两阶段 review）
